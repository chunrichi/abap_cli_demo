CLASS zcl_crw_cd_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_create_input,
             req_id            TYPE zcrw_cd-req_id,
             cycle_id          TYPE zcrw_cd-cycle_id,
             title             TYPE zcrw_cd-title,
             owner             TYPE zcrw_cd-owner,
             dev_lead          TYPE zcrw_cd-dev_lead,
             test_lead         TYPE zcrw_cd-test_lead,
             target_sys        TYPE zcrw_cd-target_sys,
             planned_import_at TYPE zcrw_cd-planned_import_at,
           END OF ty_create_input.
    TYPES tt_documents TYPE STANDARD TABLE OF zcrw_cd WITH EMPTY KEY.

    CONSTANTS: gc_status_new       TYPE zcrw_cd-status VALUE 'NEW',
               gc_status_dev       TYPE zcrw_cd-status VALUE 'IN_DEV',
               gc_status_test      TYPE zcrw_cd-status VALUE 'IN_TEST',
               gc_status_ready     TYPE zcrw_cd-status VALUE 'READY_TO_IMPORT',
               gc_status_scheduled TYPE zcrw_cd-status VALUE 'IMPORT_SCHEDULED',
               gc_status_imported  TYPE zcrw_cd-status VALUE 'IMPORTED',
               gc_status_closed    TYPE zcrw_cd-status VALUE 'CLOSED',
               gc_status_cancelled TYPE zcrw_cd-status VALUE 'CANCELLED',
               gc_approval_none    TYPE zcrw_cd-approval_state VALUE 'NONE',
               gc_approval_pending TYPE zcrw_cd-approval_state VALUE 'PENDING',
               gc_approval_ok      TYPE zcrw_cd-approval_state VALUE 'APPROVED',
               gc_approval_rej     TYPE zcrw_cd-approval_state VALUE 'REJECTED',
               gc_approval_skipped TYPE zcrw_cd-approval_state VALUE 'SKIPPED',
               gc_display_prefix   TYPE string VALUE 'CD'.

    CLASS-METHODS create
      IMPORTING is_input        TYPE ty_create_input
      RETURNING VALUE(rv_cd_id) TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_cd_id          TYPE zcrw_cd-cd_id
      RETURNING VALUE(rs_document) TYPE zcrw_cd
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_req_id     TYPE zcrw_cd-req_id OPTIONAL
                iv_status     TYPE zcrw_cd-status OPTIONAL
                iv_cycle_id   TYPE zcrw_cd-cycle_id OPTIONAL
                iv_owner      TYPE zcrw_cd-owner OPTIONAL
                iv_target_sys TYPE zcrw_cd-target_sys OPTIONAL
                iv_query      TYPE string OPTIONAL
      RETURNING VALUE(rt_documents) TYPE tt_documents.

    CLASS-METHODS update
      IMPORTING is_document TYPE zcrw_cd
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_cd_id  TYPE zcrw_cd-cd_id
                iv_status TYPE zcrw_cd-status
      RAISING   zcx_crw_error.

    CLASS-METHODS action
      IMPORTING iv_cd_id             TYPE zcrw_cd-cd_id
                iv_action            TYPE string
                iv_version           TYPE i
                iv_comment           TYPE string DEFAULT ''
                iv_planned_import_at TYPE string DEFAULT ''
                iv_cancel_schedule   TYPE abap_bool DEFAULT abap_false
      RAISING   zcx_crw_error.

    CLASS-METHODS display_id
      IMPORTING iv_cd_id            TYPE zcrw_cd-cd_id
      RETURNING VALUE(rv_display_id) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS next_id
      RETURNING VALUE(rv_cd_id) TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS check_request
      IMPORTING iv_req_id TYPE zcrw_cd-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS validate_transition
      IMPORTING iv_from TYPE zcrw_cd-status
                iv_to   TYPE zcrw_cd-status
      RAISING   zcx_crw_error.

    CLASS-METHODS bump_version
      IMPORTING iv_version        TYPE zcrw_cd-version
      RETURNING VALUE(rv_version) TYPE zcrw_cd-version.

    CLASS-METHODS has_action_history
      IMPORTING iv_cd_id         TYPE zcrw_cd-cd_id
                iv_action        TYPE string
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    CLASS-METHODS count_dev_transports
      IMPORTING iv_cd_id        TYPE zcrw_cd-cd_id
                iv_only_open    TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS count_open_dev_tasks
      IMPORTING iv_cd_id        TYPE zcrw_cd-cd_id
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS count_open_tasks
      IMPORTING iv_cd_id        TYPE zcrw_cd-cd_id
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS parent_request_type
      IMPORTING iv_cd_id    TYPE zcrw_cd-cd_id
      EXPORTING ev_req_type TYPE zcrw_req-req_type
                ev_priority TYPE zcrw_req-priority.

    CLASS-METHODS perform_action
      IMPORTING iv_cd_id             TYPE zcrw_cd-cd_id
                iv_action            TYPE string
                iv_version           TYPE i
                iv_comment           TYPE string DEFAULT ''
                iv_planned_import_at TYPE string DEFAULT ''
                iv_cancel_schedule   TYPE abap_bool DEFAULT abap_false
      RAISING   zcx_crw_error.

    CLASS-METHODS lock_document
      IMPORTING iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS unlock_document
      IMPORTING iv_cd_id TYPE zcrw_cd-cd_id.
ENDCLASS.

CLASS zcl_crw_cd_svc IMPLEMENTATION.
  METHOD create.
    DATA ls_document TYPE zcrw_cd.

    IF is_input-title IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_TITLE_REQUIRED' iv_text = 'Title is required'.
    ENDIF.
    IF is_input-req_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_REQ_REQUIRED' iv_text = 'Request id is required'.
    ENDIF.

    check_request( is_input-req_id ).

    ls_document-cd_id             = next_id( ).
    ls_document-req_id            = is_input-req_id.
    ls_document-cycle_id          = is_input-cycle_id.
    ls_document-title             = is_input-title.
    ls_document-status            = gc_status_new.
    ls_document-owner             = COND #( WHEN is_input-owner IS NOT INITIAL THEN is_input-owner ELSE sy-uname ).
    ls_document-dev_lead          = is_input-dev_lead.
    ls_document-test_lead         = is_input-test_lead.
    ls_document-target_sys        = is_input-target_sys.
    ls_document-planned_import_at = is_input-planned_import_at.
    ls_document-approval_state    = gc_approval_none.
    ls_document-version           = '000001'.
    ls_document-created_at        = zcl_crw_util=>now( ).
    ls_document-created_by        = sy-uname.
    ls_document-changed_at        = ls_document-created_at.
    ls_document-changed_by        = sy-uname.

    INSERT zcrw_cd FROM ls_document.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_INSERT' iv_text = |Could not create change document { ls_document-cd_id }|.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'CD'
                            iv_object_id   = CONV string( ls_document-cd_id )
                            iv_action      = 'CREATE'
                            iv_new_value   = CONV string( ls_document-status ) ).
        COMMIT WORK AND WAIT.
      CATCH zcx_crw_error.
        ROLLBACK WORK.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CD_AUDIT' iv_text = 'Could not write the create audit row'.
    ENDTRY.

    rv_cd_id = ls_document-cd_id.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE *
      FROM zcrw_cd
      WHERE cd_id = @iv_cd_id
      INTO @rs_document.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_NOT_FOUND' iv_text = |Change document { iv_cd_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD list.
    DATA lv_query TYPE string.

    SELECT *
      FROM zcrw_cd
      INTO TABLE @rt_documents
      ORDER BY created_at DESCENDING, cd_id DESCENDING.

    IF iv_req_id IS NOT INITIAL.
      DELETE rt_documents WHERE req_id <> iv_req_id.
    ENDIF.
    IF iv_status IS NOT INITIAL.
      DELETE rt_documents WHERE status <> iv_status.
    ENDIF.
    IF iv_cycle_id IS NOT INITIAL.
      DELETE rt_documents WHERE cycle_id <> iv_cycle_id.
    ENDIF.
    IF iv_owner IS NOT INITIAL.
      DELETE rt_documents WHERE owner <> iv_owner.
    ENDIF.
    IF iv_target_sys IS NOT INITIAL.
      DELETE rt_documents WHERE target_sys <> iv_target_sys.
    ENDIF.
    IF iv_query IS NOT INITIAL.
      lv_query = to_upper( iv_query ).
      LOOP AT rt_documents INTO DATA(ls_document).
        IF to_upper( ls_document-title ) NS lv_query.
          DELETE rt_documents.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_cd.
    DATA ls_update  TYPE zcrw_cd.

    ls_current = get( is_document-cd_id ).
    IF ls_current-version <> is_document-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION'
                  iv_text = |Change document { is_document-cd_id } was changed by another user|.
    ENDIF.
    IF ls_current-status = gc_status_closed OR ls_current-status = gc_status_cancelled.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'A closed change document cannot be edited'.
    ENDIF.

    ls_update = ls_current.
    ls_update-title             = is_document-title.
    ls_update-owner             = is_document-owner.
    ls_update-dev_lead          = is_document-dev_lead.
    ls_update-test_lead         = is_document-test_lead.
    ls_update-target_sys        = is_document-target_sys.
    ls_update-planned_import_at = is_document-planned_import_at.
    ls_update-version           = bump_version( ls_current-version ).
    ls_update-changed_at        = zcl_crw_util=>now( ).
    ls_update-changed_by        = sy-uname.

    UPDATE zcrw_cd
      SET title             = @ls_update-title,
          owner             = @ls_update-owner,
          dev_lead          = @ls_update-dev_lead,
          test_lead         = @ls_update-test_lead,
          target_sys        = @ls_update-target_sys,
          planned_import_at = @ls_update-planned_import_at,
          version           = @ls_update-version,
          changed_at        = @ls_update-changed_at,
          changed_by        = @ls_update-changed_by
      WHERE cd_id = @ls_update-cd_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION'
                  iv_text = |Could not update change document { ls_update-cd_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'CD'
                        iv_object_id   = CONV string( ls_update-cd_id )
                        iv_action      = 'UPDATE' ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD change_status.
    DATA ls_current TYPE zcrw_cd.
    DATA ls_update  TYPE zcrw_cd.

    ls_current = get( iv_cd_id ).
    validate_transition( iv_from = ls_current-status iv_to = iv_status ).

    ls_update = ls_current.
    ls_update-status     = iv_status.
    ls_update-version    = bump_version( ls_current-version ).
    ls_update-changed_at = zcl_crw_util=>now( ).
    ls_update-changed_by = sy-uname.

    IF iv_status = gc_status_closed.
      ls_update-closed_at = ls_update-changed_at.
    ENDIF.

    UPDATE zcrw_cd
      SET status     = @ls_update-status,
          version    = @ls_update-version,
          changed_at = @ls_update-changed_at,
          changed_by = @ls_update-changed_by,
          closed_at  = @ls_update-closed_at
      WHERE cd_id = @ls_update-cd_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Could not change status of { iv_cd_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'CD'
                        iv_object_id   = CONV string( iv_cd_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD action.
    lock_document( iv_cd_id ).

    TRY.
        perform_action( iv_cd_id             = iv_cd_id
                        iv_action            = iv_action
                        iv_version           = iv_version
                        iv_comment           = iv_comment
                        iv_planned_import_at = iv_planned_import_at
                        iv_cancel_schedule   = iv_cancel_schedule ).
        unlock_document( iv_cd_id ).
      CATCH zcx_crw_error INTO DATA(lx_lock_error).
        unlock_document( iv_cd_id ).
        RAISE EXCEPTION lx_lock_error.
      ENDTRY.
  ENDMETHOD.

  METHOD perform_action.
    DATA ls_current TYPE zcrw_cd.
    DATA lt_roles TYPE zcl_crw_auth=>tt_roles.
    DATA lv_user TYPE string.
    DATA lv_target TYPE string.
    DATA lv_status TYPE zcrw_cd-status.
    DATA lv_approval TYPE zcrw_cd-approval_state.
    DATA lv_version TYPE zcrw_cd-version.
    DATA lv_now TYPE char14.
    DATA lv_closed TYPE char14.
    DATA lv_planned TYPE char14.
    DATA lv_req_type TYPE zcrw_req-req_type.
    DATA lv_priority TYPE zcrw_req-priority.
    DATA lv_steps TYPE i.
    DATA lv_open_tasks TYPE i.
    DATA lv_open_dev TYPE i.
    DATA lv_tr TYPE i.
    DATA ls_sched TYPE zcrw_sched.

    lv_user = sy-uname.
    lt_roles = zcl_crw_auth=>load_roles( lv_user ).
    ls_current = get( iv_cd_id ).

    IF ls_current-version <> iv_version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The change document was changed by another user'.
    ENDIF.

    lv_target = zcl_crw_workflow=>target_status( iv_object_type = zcl_crw_workflow=>gc_obj_cd
                                                 iv_from        = CONV string( ls_current-status )
                                                 iv_action      = iv_action ).
    IF lv_target IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION'
                  iv_text = |Current status { ls_current-status } does not allow { iv_action }|.
    ENDIF.

*   Role checks per action (ADMIN passes every check inside require_any).
    CASE iv_action.
      WHEN zcl_crw_workflow=>gc_act_start_dev.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_developer )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        IF ls_current-owner IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'The change document has no owner'.
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_submit_test.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_developer )
                                                                  ( zcl_crw_auth=>gc_tester )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        lv_open_dev = count_open_dev_tasks( iv_cd_id ).
        IF lv_open_dev > 0.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED'
                      iv_text = |{ lv_open_dev } development task(s) are still open|.
        ENDIF.
        parent_request_type( EXPORTING iv_cd_id    = iv_cd_id
                             IMPORTING ev_req_type = lv_req_type
                                       ev_priority = lv_priority ).
        IF lv_req_type = 'STD'.
          lv_tr = count_dev_transports( iv_cd_id = iv_cd_id iv_only_open = abap_false ).
          IF lv_tr = 0.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'At least one DEV transport must be linked'.
          ENDIF.
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_pass_test.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_tester )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
      WHEN zcl_crw_workflow=>gc_act_submit_approval.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        IF has_action_history( iv_cd_id = iv_cd_id iv_action = zcl_crw_workflow=>gc_act_pass_test ) = abap_false.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'The test result must be recorded before approval'.
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_mark_ready.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_release_manager )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        IF has_action_history( iv_cd_id = iv_cd_id iv_action = zcl_crw_workflow=>gc_act_pass_test ) = abap_false.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'The test result is missing'.
        ENDIF.
        IF ls_current-approval_state <> gc_approval_ok.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'The change document approval is not completed'.
        ENDIF.
        lv_tr = count_dev_transports( iv_cd_id = iv_cd_id iv_only_open = abap_true ).
        IF lv_tr > 0.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED'
                      iv_text = |{ lv_tr } DEV transport(s) are not released|.
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_schedule_import.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_release_manager )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
      WHEN zcl_crw_workflow=>gc_act_confirm_import.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_release_manager )
                                                                  ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
      WHEN zcl_crw_workflow=>gc_act_close.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        lv_open_tasks = count_open_tasks( iv_cd_id ).
        IF lv_open_tasks > 0.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED'
                      iv_text = |{ lv_open_tasks } task(s) are still open|.
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

*   Side effects that create or terminate serving records before the status write.
    lv_approval = ls_current-approval_state.
    lv_planned = ls_current-planned_import_at.

    IF iv_action = zcl_crw_workflow=>gc_act_submit_approval.
      parent_request_type( EXPORTING iv_cd_id    = iv_cd_id
                           IMPORTING ev_req_type = lv_req_type
                                     ev_priority = lv_priority ).
      lv_steps = zcl_crw_appr_svc=>generate_steps( iv_object_type = zcl_crw_workflow=>gc_obj_cd
                                                   iv_object_id   = CONV string( iv_cd_id )
                                                   iv_req_type    = CONV string( lv_req_type )
                                                   iv_priority    = CONV string( lv_priority ) ).
      IF lv_steps = 0.
        lv_approval = gc_approval_ok.
      ELSE.
        lv_approval = gc_approval_pending.
      ENDIF.
    ELSEIF iv_action = zcl_crw_workflow=>gc_act_schedule_import.
      IF iv_cancel_schedule = abap_true.
        ls_sched = zcl_crw_schedule_svc=>active_for_object( iv_object_type = zcl_crw_schedule_svc=>gc_obj_cd
                                                            iv_object_id   = CONV string( iv_cd_id ) ).
        IF ls_sched-sched_id IS NOT INITIAL.
          zcl_crw_schedule_svc=>cancel( iv_sched_id = ls_sched-sched_id iv_note = iv_comment ).
        ENDIF.
        lv_planned = ''.
        lv_target = gc_status_ready.
      ELSE.
        lv_planned = zcl_crw_json=>parse_timestamp( iv_planned_import_at ).
        IF lv_planned IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'A planned import time is required'.
        ENDIF.
        zcl_crw_schedule_svc=>create_or_update( iv_object_type  = zcl_crw_schedule_svc=>gc_obj_cd
                                                iv_object_id    = CONV string( iv_cd_id )
                                                iv_target_sys   = CONV string( ls_current-target_sys )
                                                iv_scheduled_at = lv_planned
                                                iv_note         = iv_comment ).
        lv_target = gc_status_scheduled.
      ENDIF.
    ELSEIF iv_action = zcl_crw_workflow=>gc_act_confirm_import.
      ls_sched = zcl_crw_schedule_svc=>active_for_object( iv_object_type = zcl_crw_schedule_svc=>gc_obj_cd
                                                          iv_object_id   = CONV string( iv_cd_id ) ).
      IF ls_sched-sched_id IS NOT INITIAL.
        zcl_crw_schedule_svc=>confirm( iv_sched_id = ls_sched-sched_id iv_note = iv_comment ).
      ENDIF.
    ELSEIF iv_action = zcl_crw_workflow=>gc_act_cancel.
      zcl_crw_schedule_svc=>cancel_for_object( iv_object_type = zcl_crw_schedule_svc=>gc_obj_cd
                                               iv_object_id   = CONV string( iv_cd_id )
                                               iv_note        = iv_comment ).
      IF lv_approval = gc_approval_pending.
        lv_approval = gc_approval_skipped.
      ENDIF.
      zcl_crw_appr_svc=>skip_pending( iv_object_type = zcl_crw_workflow=>gc_obj_cd
                                      iv_object_id   = CONV string( iv_cd_id )
                                      iv_action      = iv_action ).
    ENDIF.

    lv_status = lv_target.
    lv_version = bump_version( ls_current-version ).
    lv_now = zcl_crw_util=>now( ).
    lv_closed = ls_current-closed_at.

    IF lv_target = gc_status_closed OR lv_target = gc_status_cancelled.
      lv_closed = lv_now.
    ENDIF.

    UPDATE zcrw_cd
      SET status            = @lv_status,
          approval_state    = @lv_approval,
          planned_import_at = @lv_planned,
          version           = @lv_version,
          changed_at        = @lv_now,
          changed_by        = @sy-uname,
          closed_at         = @lv_closed
      WHERE cd_id = @iv_cd_id
        AND version = @iv_version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The change document was changed by another user'.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'CD'
                        iv_object_id   = CONV string( iv_cd_id )
                        iv_action      = iv_action
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( lv_status )
                        iv_comment     = iv_comment ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD display_id.
    rv_display_id = |{ gc_display_prefix }-{ iv_cd_id }|.
  ENDMETHOD.

  METHOD next_id.
    DATA lv_number TYPE inri-nr.

    lv_number = zcl_crw_number=>next( 'ZCRW_CD' ).
    rv_cd_id = zcl_crw_util=>number_id( lv_number ).
  ENDMETHOD.

  METHOD check_request.
    SELECT SINGLE req_id
      FROM zcrw_req
      WHERE req_id = @iv_req_id
      INTO @DATA(lv_req_id).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_REQ_NOT_FOUND' iv_text = |Change request { iv_req_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD validate_transition.
    IF zcl_crw_workflow=>is_valid( iv_object_type = zcl_crw_workflow=>gc_obj_cd
                                    iv_from        = CONV string( iv_from )
                                    iv_action      = COND string( WHEN iv_to = zcl_crw_workflow=>gc_cd_dev THEN zcl_crw_workflow=>gc_act_start_dev
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_test THEN zcl_crw_workflow=>gc_act_submit_test
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_ready THEN zcl_crw_workflow=>gc_act_mark_ready
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_scheduled THEN zcl_crw_workflow=>gc_act_schedule_import
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_imported THEN zcl_crw_workflow=>gc_act_confirm_import
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_closed THEN zcl_crw_workflow=>gc_act_close
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_cd_cancelled THEN zcl_crw_workflow=>gc_act_cancel
                                                                   ELSE zcl_crw_workflow=>gc_act_start_dev ) ) = abap_false.
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

  METHOD has_action_history.
    DATA lv_object_type TYPE zcrw_hist-object_type.
    DATA lv_count TYPE i.

    lv_object_type = 'CD'.

    SELECT COUNT(*)
      FROM zcrw_hist
      WHERE object_type = @lv_object_type
        AND object_id   = @iv_cd_id
        AND action      = @iv_action
      INTO @lv_count.

    rv_exists = xsdbool( lv_count > 0 ).
  ENDMETHOD.

  METHOD count_dev_transports.
    DATA lv_kind TYPE zcrw_tr-tr_kind.
    DATA lv_released TYPE zcrw_tr-tr_status.

    lv_kind = 'DEV'.
    lv_released = 'R'.

    IF iv_only_open = abap_true.
      SELECT COUNT(*)
        FROM zcrw_tr
        WHERE cd_id     = @iv_cd_id
          AND tr_kind   = @lv_kind
          AND tr_status <> @lv_released
        INTO @rv_count.
    ELSE.
      SELECT COUNT(*)
        FROM zcrw_tr
        WHERE cd_id   = @iv_cd_id
          AND tr_kind = @lv_kind
        INTO @rv_count.
    ENDIF.
  ENDMETHOD.

  METHOD count_open_dev_tasks.
    DATA lv_dev TYPE zcrw_task-task_type.
    DATA lv_done TYPE zcrw_task-status.
    DATA lv_cancelled TYPE zcrw_task-status.

    lv_dev = 'DEV'.
    lv_done = 'DONE'.
    lv_cancelled = 'CANCELLED'.

    SELECT COUNT(*)
      FROM zcrw_task
      WHERE cd_id     = @iv_cd_id
        AND task_type = @lv_dev
        AND status   <> @lv_done
        AND status   <> @lv_cancelled
      INTO @rv_count.
  ENDMETHOD.

  METHOD count_open_tasks.
    DATA lv_done TYPE zcrw_task-status.
    DATA lv_cancelled TYPE zcrw_task-status.

    lv_done = 'DONE'.
    lv_cancelled = 'CANCELLED'.

    SELECT COUNT(*)
      FROM zcrw_task
      WHERE cd_id   = @iv_cd_id
        AND status <> @lv_done
        AND status <> @lv_cancelled
      INTO @rv_count.
  ENDMETHOD.

  METHOD parent_request_type.
    SELECT SINGLE r~req_type, r~priority
      FROM zcrw_req AS r
      INNER JOIN zcrw_cd AS c ON r~req_id = c~req_id
      WHERE c~cd_id = @iv_cd_id
      INTO (@ev_req_type, @ev_priority).
  ENDMETHOD.
  METHOD lock_document.
    CALL FUNCTION 'ENQUEUE_EZCRW_CD'
      EXPORTING
        cd_id         = iv_cd_id
      EXCEPTIONS
        foreign_lock  = 1
        system_failure = 2
        OTHERS        = 3.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'OBJECT_LOCKED'
                  iv_text = 'The change document is locked by another user'.
    ENDIF.
  ENDMETHOD.

  METHOD unlock_document.
    CALL FUNCTION 'DEQUEUE_EZCRW_CD'
      EXPORTING
        cd_id = iv_cd_id.
  ENDMETHOD.

ENDCLASS.
