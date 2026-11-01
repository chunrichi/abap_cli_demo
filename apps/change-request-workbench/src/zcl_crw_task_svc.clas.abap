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
               gc_display_prefix     TYPE string VALUE 'T',
               gc_subtask_prefix     TYPE string VALUE 'ST'.

    CLASS-METHODS create
      IMPORTING is_input          TYPE ty_create_input
      RETURNING VALUE(rv_task_id) TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_task_id     TYPE zcrw_task-task_id
      RETURNING VALUE(rs_task) TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_cd_id         TYPE zcrw_task-cd_id OPTIONAL
                iv_req_id        TYPE zcrw_task-req_id OPTIONAL
                iv_status        TYPE zcrw_task-status OPTIONAL
                iv_assignee      TYPE zcrw_task-assignee OPTIONAL
                iv_task_type     TYPE zcrw_task-task_type OPTIONAL
                iv_parent_task_id TYPE zcrw_task-parent_task_id OPTIONAL
                iv_due_from      TYPE dats OPTIONAL
                iv_due_to        TYPE dats OPTIONAL
                iv_query         TYPE string OPTIONAL
      RETURNING VALUE(rt_tasks) TYPE tt_tasks.

    CLASS-METHODS update
      IMPORTING is_task TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_task_id TYPE zcrw_task-task_id
                iv_status  TYPE zcrw_task-status
      RAISING   zcx_crw_error.

    CLASS-METHODS action
      IMPORTING iv_task_id TYPE zcrw_task-task_id
                iv_action  TYPE string
                iv_version TYPE i
                iv_comment TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS display_id
      IMPORTING iv_task_id          TYPE zcrw_task-task_id
                iv_task_level       TYPE zcrw_task-task_level DEFAULT ''
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
      RETURNING VALUE(rs_parent)  TYPE zcrw_task
      RAISING   zcx_crw_error.

    CLASS-METHODS validate_transition
      IMPORTING iv_from TYPE zcrw_task-status
                iv_to   TYPE zcrw_task-status
      RAISING   zcx_crw_error.

    CLASS-METHODS bump_version
      IMPORTING iv_version        TYPE zcrw_task-version
      RETURNING VALUE(rv_version) TYPE zcrw_task-version.

    CLASS-METHODS count_open_children
      IMPORTING iv_task_id      TYPE zcrw_task-task_id
      RETURNING VALUE(rv_count) TYPE i.
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
                            iv_action      = COND #( WHEN ls_task-parent_task_id IS INITIAL THEN 'CREATE_TASK' ELSE 'CREATE_SUBTASK' )
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
    DATA lv_query TYPE string.

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
    IF iv_assignee IS NOT INITIAL.
      DELETE rt_tasks WHERE assignee <> iv_assignee.
    ENDIF.
    IF iv_task_type IS NOT INITIAL.
      DELETE rt_tasks WHERE task_type <> iv_task_type.
    ENDIF.
    IF iv_parent_task_id IS NOT INITIAL.
      DELETE rt_tasks WHERE parent_task_id <> iv_parent_task_id.
    ENDIF.
    IF iv_due_from IS NOT INITIAL.
      DELETE rt_tasks WHERE due_date < iv_due_from.
    ENDIF.
    IF iv_due_to IS NOT INITIAL.
      DELETE rt_tasks WHERE due_date > iv_due_to.
    ENDIF.
    IF iv_query IS NOT INITIAL.
      lv_query = to_upper( iv_query ).
      LOOP AT rt_tasks INTO DATA(ls_task).
        IF to_upper( ls_task-title ) NS lv_query.
          DELETE rt_tasks.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_task.
    DATA ls_update  TYPE zcrw_task.

    ls_current = get( is_task-task_id ).
    IF ls_current-version <> is_task-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION'
                  iv_text = |Task { is_task-task_id } was changed by another user|.
    ENDIF.

    ls_update = ls_current.
    ls_update-title     = is_task-title.
    ls_update-assignee  = is_task-assignee.
    ls_update-due_date  = is_task-due_date.
    ls_update-est_hours = is_task-est_hours.
    ls_update-version   = bump_version( ls_current-version ).
    ls_update-changed_at = zcl_crw_util=>now( ).
    ls_update-changed_by = sy-uname.

    UPDATE zcrw_task
      SET title      = @ls_update-title,
          assignee   = @ls_update-assignee,
          due_date   = @ls_update-due_date,
          est_hours  = @ls_update-est_hours,
          version    = @ls_update-version,
          changed_at = @ls_update-changed_at,
          changed_by = @ls_update-changed_by
      WHERE task_id = @ls_update-task_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Could not update task { ls_update-task_id }|.
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

    UPDATE zcrw_task
      SET status     = @ls_update-status,
          version    = @ls_update-version,
          changed_at = @ls_update-changed_at,
          changed_by = @ls_update-changed_by
      WHERE task_id = @ls_update-task_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Could not change status of { iv_task_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'TASK'
                        iv_object_id   = CONV string( iv_task_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD action.
    DATA ls_current TYPE zcrw_task.
    DATA lt_roles TYPE zcl_crw_auth=>tt_roles.
    DATA lv_user TYPE string.
    DATA lv_target TYPE string.
    DATA lv_status TYPE zcrw_task-status.
    DATA lv_version TYPE zcrw_task-version.
    DATA lv_now TYPE char14.
    DATA lv_open_children TYPE i.

    lv_user = sy-uname.
    lt_roles = zcl_crw_auth=>load_roles( lv_user ).
    ls_current = get( iv_task_id ).

    IF ls_current-version <> iv_version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The task was changed by another user'.
    ENDIF.

    lv_target = zcl_crw_workflow=>target_status( iv_object_type = zcl_crw_workflow=>gc_obj_task
                                                 iv_from        = CONV string( ls_current-status )
                                                 iv_action      = iv_action ).
    IF lv_target IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION'
                  iv_text = |Current status { ls_current-status } does not allow { iv_action }|.
    ENDIF.

*   Task actions are limited to the assignee, the owning team and managers.
    CASE iv_action.
      WHEN zcl_crw_workflow=>gc_act_start OR zcl_crw_workflow=>gc_act_done.
        IF lv_user <> ls_current-assignee.
          zcl_crw_auth=>require_any( it_roles = lt_roles
                                     iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_developer )
                                                                    ( zcl_crw_auth=>gc_tester )
                                                                    ( zcl_crw_auth=>gc_change_manager ) )
                                     iv_action = iv_action ).
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_cancel.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        IF iv_comment IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'A cancel reason is required'.
        ENDIF.
    ENDCASE.

    IF iv_action = zcl_crw_workflow=>gc_act_done AND ls_current-task_level = gc_level_task.
      lv_open_children = count_open_children( iv_task_id ).
      IF lv_open_children > 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'GUARD_FAILED'
                    iv_text = |{ lv_open_children } subtask(s) are still open|.
      ENDIF.
    ENDIF.

    lv_status = lv_target.
    lv_version = bump_version( ls_current-version ).
    lv_now = zcl_crw_util=>now( ).

    UPDATE zcrw_task
      SET status     = @lv_status,
          version    = @lv_version,
          changed_at = @lv_now,
          changed_by = @sy-uname
      WHERE task_id = @iv_task_id
        AND version = @iv_version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The task was changed by another user'.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'TASK'
                        iv_object_id   = CONV string( iv_task_id )
                        iv_action      = iv_action
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( lv_status )
                        iv_comment     = iv_comment ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD display_id.
    IF iv_task_level = gc_level_subtask.
      rv_display_id = |{ gc_subtask_prefix }-{ iv_task_id }|.
    ELSE.
      rv_display_id = |{ gc_display_prefix }-{ iv_task_id }|.
    ENDIF.
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
    IF rs_parent-task_level <> gc_level_task.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TASK_PARENT_INVALID' iv_text = 'A subtask can only be added below a task'.
    ENDIF.
  ENDMETHOD.

  METHOD validate_transition.
    IF zcl_crw_workflow=>is_valid( iv_object_type = zcl_crw_workflow=>gc_obj_task
                                    iv_from        = CONV string( iv_from )
                                    iv_action      = COND string( WHEN iv_to = zcl_crw_workflow=>gc_task_progress THEN zcl_crw_workflow=>gc_act_start
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_task_done THEN zcl_crw_workflow=>gc_act_done
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_task_cancelled THEN zcl_crw_workflow=>gc_act_cancel
                                                                   ELSE zcl_crw_workflow=>gc_act_start ) ) = abap_false.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
    ENDIF.
  ENDMETHOD.

  METHOD bump_version.
    DATA lv_version TYPE i.

    lv_version = iv_version.
    lv_version = lv_version + 1.
    rv_version = lv_version.
  ENDMETHOD.

  METHOD count_open_children.
    DATA lv_done TYPE zcrw_task-status.
    DATA lv_cancelled TYPE zcrw_task-status.

    lv_done = gc_status_done.
    lv_cancelled = gc_status_cancelled.

    SELECT COUNT(*)
      FROM zcrw_task
      WHERE parent_task_id = @iv_task_id
        AND status        <> @lv_done
        AND status        <> @lv_cancelled
      INTO @rv_count.
  ENDMETHOD.
ENDCLASS.
