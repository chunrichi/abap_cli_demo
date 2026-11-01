CLASS zcl_crw_task_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_create_input,
             req_id         TYPE zcrw_task-req_id,
             cd_id          TYPE zcrw_task-cd_id,
             parent_task_id TYPE zcrw_task-parent_task_id,
             task_type      TYPE zcrw_task-task_type,
             title          TYPE zcrw_task-title,
             assignee       TYPE zcrw_task-assignee,
             due_date       TYPE zcrw_task-due_date,
             est_hours      TYPE zcrw_task-est_hours,
           END OF ty_create_input.
    TYPES tt_tasks TYPE STANDARD TABLE OF zcrw_task WITH EMPTY KEY.

    CONSTANTS: gc_status_open        TYPE zcrw_task-status VALUE 'OPEN',
               gc_status_in_progress TYPE zcrw_task-status VALUE 'IN_PROGRESS',
               gc_status_done        TYPE zcrw_task-status VALUE 'DONE',
               gc_status_cancelled   TYPE zcrw_task-status VALUE 'CANCELLED',
               gc_level_task         TYPE zcrw_task-task_level VALUE 'T',
               gc_level_subtask      TYPE zcrw_task-task_level VALUE 'S',
               gc_display_prefix     TYPE string VALUE 'T'.

    CLASS-METHODS create
      IMPORTING is_input TYPE ty_create_input
      RETURNING VALUE(rv_task_id) TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_task_id TYPE zcrw_task-task_id
      RETURNING VALUE(rs_task) TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_cd_id  TYPE zcrw_task-cd_id OPTIONAL
                iv_req_id TYPE zcrw_task-req_id OPTIONAL
                iv_status TYPE zcrw_task-status OPTIONAL
      RETURNING VALUE(rt_tasks) TYPE tt_tasks.

    CLASS-METHODS update
      IMPORTING is_task TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_task_id TYPE zcrw_task-task_id
                iv_status  TYPE zcrw_task-status
      RAISING   zcx_crw_error.

    CLASS-METHODS display_id
      IMPORTING iv_task_id TYPE zcrw_task-task_id
      RETURNING VALUE(rv_display_id) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS next_id
      RETURNING VALUE(rv_task_id) TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS check_cd
      IMPORTING iv_cd_id TYPE zcrw_task-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS read_parent
      IMPORTING iv_parent_task_id TYPE zcrw_task-parent_task_id
      RETURNING VALUE(rs_parent) TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS validate_transition
      IMPORTING iv_from TYPE zcrw_task-status
                iv_to   TYPE zcrw_task-status
      RAISING   zcx_crw_error.

    CLASS-METHODS bump_version
      IMPORTING iv_version TYPE zcrw_task-version
      RETURNING VALUE(rv_version) TYPE zcrw_task-version.
ENDCLASS.

CLASS zcl_crw_task_svc IMPLEMENTATION.
  METHOD create.
    DATA ls_task TYPE zcrw_task.

    IF is_input-title IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_TITLE_REQUIRED' iv_text = 'Title is required'.
    ENDIF.
    IF is_input-cd_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_CD_REQUIRED' iv_text = 'Change document id is required'.
    ENDIF.

    check_cd( is_input-cd_id ).

    IF is_input-parent_task_id IS NOT INITIAL.
      DATA(ls_parent) = read_parent( is_input-parent_task_id ).
      ls_task-task_level = gc_level_subtask.
      ls_task-req_id = COND #( WHEN is_input-req_id IS NOT INITIAL THEN is_input-req_id ELSE ls_parent-req_id ).
    ELSE.
      ls_task-task_level = gc_level_task.
      ls_task-parent_task_id = ''.
      ls_task-req_id = is_input-req_id.
    ENDIF.

    ls_task-task_id   = next_id( ).
    ls_task-cd_id     = is_input-cd_id.
    ls_task-parent_task_id = is_input-parent_task_id.
    ls_task-task_type = is_input-task_type.
    ls_task-title     = is_input-title.
    ls_task-assignee  = COND #( WHEN is_input-assignee IS NOT INITIAL THEN is_input-assignee ELSE sy-uname ).
    ls_task-status    = gc_status_open.
    ls_task-due_date  = is_input-due_date.
    ls_task-est_hours = is_input-est_hours.
    ls_task-version   = '000001'.
    ls_task-created_at = zcl_crw_util=>now( ).
    ls_task-created_by = sy-uname.
    ls_task-changed_at = ls_task-created_at.
    ls_task-changed_by = sy-uname.

    INSERT zcrw_task FROM ls_task.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_INSERT' iv_text = |Could not create task { ls_task-task_id }|.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'TASK'
                            iv_object_id   = CONV string( ls_task-task_id )
                            iv_action      = 'CREATE'
                            iv_new_value   = CONV string( ls_task-status ) ).
        COMMIT WORK AND WAIT.
      CATCH zcx_crw_error.
        ROLLBACK WORK.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'TASK_AUDIT' iv_text = 'Could not write the create audit row'.
    ENDTRY.

    rv_task_id = ls_task-task_id.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE *
      FROM zcrw_task
      WHERE task_id = @iv_task_id
      INTO @rs_task.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_NOT_FOUND' iv_text = |Task { iv_task_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD list.
    SELECT *
      FROM zcrw_task
      INTO TABLE @rt_tasks
      ORDER BY created_at DESCENDING, task_id DESCENDING.

    IF iv_cd_id IS NOT INITIAL.
      DELETE rt_tasks WHERE cd_id <> iv_cd_id.
    ENDIF.
    IF iv_req_id IS NOT INITIAL.
      DELETE rt_tasks WHERE req_id <> iv_req_id.
    ENDIF.
    IF iv_status IS NOT INITIAL.
      DELETE rt_tasks WHERE status <> iv_status.
    ENDIF.
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_task.
    DATA ls_update  TYPE zcrw_task.

    ls_current = get( is_task-task_id ).
    IF ls_current-version <> is_task-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_VERSION_CONFLICT' iv_text = |Task { is_task-task_id } was changed by another user|.
    ENDIF.

    ls_update = ls_current.
    ls_update-task_type = is_task-task_type.
    ls_update-title     = is_task-title.
    ls_update-assignee  = is_task-assignee.
    ls_update-due_date  = is_task-due_date.
    ls_update-est_hours = is_task-est_hours.
    ls_update-version   = bump_version( ls_current-version ).
    ls_update-changed_at = zcl_crw_util=>now( ).
    ls_update-changed_by = sy-uname.

    UPDATE zcrw_task FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_UPDATE' iv_text = |Could not update task { ls_update-task_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'TASK'
                        iv_object_id   = CONV string( ls_update-task_id )
                        iv_action      = 'UPDATE' ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD change_status.
    DATA ls_current TYPE zcrw_task.
    DATA ls_update  TYPE zcrw_task.

    ls_current = get( iv_task_id ).
    validate_transition( iv_from = ls_current-status iv_to = iv_status ).

    ls_update = ls_current.
    ls_update-status     = iv_status.
    ls_update-version    = bump_version( ls_current-version ).
    ls_update-changed_at = zcl_crw_util=>now( ).
    ls_update-changed_by = sy-uname.

    UPDATE zcrw_task FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_STATUS_UPDATE' iv_text = |Could not change status of { iv_task_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'TASK'
                        iv_object_id   = CONV string( iv_task_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD display_id.
    rv_display_id = |{ gc_display_prefix }-{ iv_task_id }|.
  ENDMETHOD.

  METHOD next_id.
    DATA lv_number TYPE inri-nr.

    lv_number = zcl_crw_number=>next( 'ZCRW_TASK' ).
    rv_task_id = zcl_crw_util=>number_id( lv_number ).
  ENDMETHOD.

  METHOD check_cd.
    SELECT SINGLE cd_id
      FROM zcrw_cd
      WHERE cd_id = @iv_cd_id
      INTO @DATA(lv_cd_id).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_CD_NOT_FOUND' iv_text = |Change document { iv_cd_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD read_parent.
    rs_parent = get( iv_parent_task_id ).
  ENDMETHOD.

  METHOD validate_transition.
    CASE iv_from.
      WHEN gc_status_open.
        IF iv_to <> gc_status_in_progress AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'TASK_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_in_progress.
        IF iv_to <> gc_status_done AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'TASK_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'TASK_TERMINAL' iv_text = |Task is already done or cancelled|.
    ENDCASE.
  ENDMETHOD.

  METHOD bump_version.
    DATA lv_version TYPE i.

    lv_version = iv_version.
    lv_version = lv_version + 1.
    rv_version = lv_version.
  ENDMETHOD.
ENDCLASS.
