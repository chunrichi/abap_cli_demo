CLASS zcl_crw_request_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_create_input,
             req_type      TYPE zcrw_req-req_type,
             title         TYPE zcrw_req-title,
             description   TYPE zcrw_req-description,
             priority      TYPE zcrw_req-priority,
             component     TYPE zcrw_req-component,
             cycle_id      TYPE zcrw_req-cycle_id,
             requester     TYPE zcrw_req-requester,
             owner         TYPE zcrw_req-owner,
             planned_start TYPE zcrw_req-planned_start,
             planned_end   TYPE zcrw_req-planned_end,
             due_date      TYPE zcrw_req-due_date,
           END OF ty_create_input.
    TYPES tt_requests TYPE STANDARD TABLE OF zcrw_req WITH EMPTY KEY.
    TYPES tt_notes TYPE STANDARD TABLE OF zcrw_note WITH EMPTY KEY.

    CONSTANTS: gc_status_new       TYPE zcrw_req-status VALUE 'NEW',
               gc_status_pending   TYPE zcrw_req-status VALUE 'PENDING_APPROVAL',
               gc_status_approved  TYPE zcrw_req-status VALUE 'APPROVED',
               gc_status_rejected  TYPE zcrw_req-status VALUE 'REJECTED',
               gc_status_progress  TYPE zcrw_req-status VALUE 'IN_PROGRESS',
               gc_status_closed    TYPE zcrw_req-status VALUE 'CLOSED',
               gc_status_cancelled TYPE zcrw_req-status VALUE 'CANCELLED',
               gc_approval_none    TYPE zcrw_req-approval_state VALUE 'NONE',
               gc_approval_pending TYPE zcrw_req-approval_state VALUE 'PENDING',
               gc_approval_ok      TYPE zcrw_req-approval_state VALUE 'APPROVED',
               gc_approval_rej     TYPE zcrw_req-approval_state VALUE 'REJECTED',
               gc_approval_skipped TYPE zcrw_req-approval_state VALUE 'SKIPPED',
               gc_display_prefix   TYPE string VALUE 'CR'.

    CLASS-METHODS create
      IMPORTING is_input        TYPE ty_create_input
      RETURNING VALUE(rv_req_id) TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_req_id        TYPE zcrw_req-req_id
      RETURNING VALUE(rs_request) TYPE zcrw_req
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_status       TYPE zcrw_req-status OPTIONAL
                iv_owner        TYPE zcrw_req-owner OPTIONAL
                iv_requester    TYPE zcrw_req-requester OPTIONAL
                iv_request_type TYPE zcrw_req-req_type OPTIONAL
                iv_priority     TYPE zcrw_req-priority OPTIONAL
                iv_component    TYPE zcrw_req-component OPTIONAL
                iv_cycle_id     TYPE zcrw_req-cycle_id OPTIONAL
                iv_query        TYPE string OPTIONAL
      RETURNING VALUE(rt_requests) TYPE tt_requests.

    CLASS-METHODS update
      IMPORTING is_request TYPE zcrw_req
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_req_id TYPE zcrw_req-req_id
                iv_status TYPE zcrw_req-status
      RAISING   zcx_crw_error.

    CLASS-METHODS action
      IMPORTING iv_req_id  TYPE zcrw_req-req_id
                iv_action  TYPE string
                iv_version TYPE i
                iv_comment TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS notes_add
      IMPORTING iv_req_id          TYPE zcrw_req-req_id
                iv_text            TYPE string
                iv_visibility      TYPE string DEFAULT 'PUBLIC'
      RETURNING VALUE(rv_note_id)  TYPE zcrw_note-note_id
      RAISING   zcx_crw_error.

    CLASS-METHODS notes_list
      IMPORTING iv_req_id       TYPE zcrw_req-req_id
      RETURNING VALUE(rt_notes) TYPE tt_notes.

    CLASS-METHODS display_id
      IMPORTING iv_req_id           TYPE zcrw_req-req_id
      RETURNING VALUE(rv_display_id) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS next_id
      RETURNING VALUE(rv_req_id) TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS validate_transition
      IMPORTING iv_from TYPE zcrw_req-status
                iv_to   TYPE zcrw_req-status
      RAISING   zcx_crw_error.

    CLASS-METHODS bump_version
      IMPORTING iv_version       TYPE zcrw_req-version
      RETURNING VALUE(rv_version) TYPE zcrw_req-version.

    CLASS-METHODS check_submit_fields
      IMPORTING is_request TYPE zcrw_req
      RAISING   zcx_crw_error.

    CLASS-METHODS check_close_guard
      IMPORTING iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS perform_action
      IMPORTING iv_req_id  TYPE zcrw_req-req_id
                iv_action  TYPE string
                iv_version TYPE i
                iv_comment TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS lock_request
      IMPORTING iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS unlock_request
      IMPORTING iv_req_id TYPE zcrw_req-req_id.
ENDCLASS.

CLASS zcl_crw_request_svc IMPLEMENTATION.
  METHOD create.
    DATA ls_request TYPE zcrw_req.

    IF is_input-title IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_TITLE_REQUIRED' iv_text = 'Title is required'.
    ENDIF.
    IF is_input-req_type IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_TYPE_REQUIRED' iv_text = 'Request type is required'.
    ENDIF.

    ls_request-req_id       = next_id( ).
    ls_request-req_type     = is_input-req_type.
    ls_request-title        = is_input-title.
    ls_request-description  = is_input-description.
    ls_request-status       = gc_status_new.
    ls_request-priority     = is_input-priority.
    ls_request-component    = is_input-component.
    ls_request-cycle_id     = is_input-cycle_id.
    ls_request-requester    = COND #( WHEN is_input-requester IS NOT INITIAL THEN is_input-requester ELSE sy-uname ).
    ls_request-owner        = COND #( WHEN is_input-owner IS NOT INITIAL THEN is_input-owner ELSE sy-uname ).
    ls_request-approval_state = gc_approval_none.
    ls_request-planned_start = is_input-planned_start.
    ls_request-planned_end   = is_input-planned_end.
    ls_request-due_date      = is_input-due_date.
    ls_request-version       = '000001'.
    ls_request-created_at    = zcl_crw_util=>now( ).
    ls_request-created_by    = sy-uname.
    ls_request-changed_at    = ls_request-created_at.
    ls_request-changed_by    = sy-uname.

    INSERT zcrw_req FROM ls_request.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_INSERT' iv_text = |Could not create request { ls_request-req_id }|.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'REQ'
                            iv_object_id   = CONV string( ls_request-req_id )
                            iv_action      = 'CREATE'
                            iv_new_value   = CONV string( ls_request-status ) ).
        COMMIT WORK AND WAIT.
      CATCH zcx_crw_error.
        ROLLBACK WORK.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CR_AUDIT' iv_text = 'Could not write the create audit row'.
    ENDTRY.

    rv_req_id = ls_request-req_id.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE *
      FROM zcrw_req
      WHERE req_id = @iv_req_id
      INTO @rs_request.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_NOT_FOUND' iv_text = |Change request { iv_req_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD list.
    DATA lv_query TYPE string.

    SELECT *
      FROM zcrw_req
      INTO TABLE @rt_requests
      ORDER BY created_at DESCENDING, req_id DESCENDING.

    IF iv_status IS NOT INITIAL.
      DELETE rt_requests WHERE status <> iv_status.
    ENDIF.
    IF iv_owner IS NOT INITIAL.
      DELETE rt_requests WHERE owner <> iv_owner.
    ENDIF.
    IF iv_requester IS NOT INITIAL.
      DELETE rt_requests WHERE requester <> iv_requester.
    ENDIF.
    IF iv_request_type IS NOT INITIAL.
      DELETE rt_requests WHERE req_type <> iv_request_type.
    ENDIF.
    IF iv_priority IS NOT INITIAL.
      DELETE rt_requests WHERE priority <> iv_priority.
    ENDIF.
    IF iv_component IS NOT INITIAL.
      DELETE rt_requests WHERE component <> iv_component.
    ENDIF.
    IF iv_cycle_id IS NOT INITIAL.
      DELETE rt_requests WHERE cycle_id <> iv_cycle_id.
    ENDIF.
    IF iv_query IS NOT INITIAL.
      lv_query = to_upper( iv_query ).
      LOOP AT rt_requests INTO DATA(ls_request).
        IF to_upper( ls_request-title ) NS lv_query
            AND to_upper( ls_request-description ) NS lv_query.
          DELETE rt_requests.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_req.
    DATA ls_update  TYPE zcrw_req.

    ls_current = get( is_request-req_id ).
    IF ls_current-version <> is_request-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Request { is_request-req_id } was changed by another user|.
    ENDIF.
    IF ls_current-status <> gc_status_new AND ls_current-status <> gc_status_rejected.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'Only NEW or REJECTED requests can be edited'.
    ENDIF.

    ls_update = ls_current.
    ls_update-title         = is_request-title.
    ls_update-description   = is_request-description.
    ls_update-priority      = is_request-priority.
    ls_update-component     = is_request-component.
    ls_update-cycle_id      = is_request-cycle_id.
    ls_update-owner         = is_request-owner.
    ls_update-planned_start = is_request-planned_start.
    ls_update-planned_end   = is_request-planned_end.
    ls_update-due_date      = is_request-due_date.
    ls_update-version       = bump_version( ls_current-version ).
    ls_update-changed_at    = zcl_crw_util=>now( ).
    ls_update-changed_by    = sy-uname.

    UPDATE zcrw_req
      SET title         = @ls_update-title,
          description   = @ls_update-description,
          priority      = @ls_update-priority,
          component     = @ls_update-component,
          cycle_id      = @ls_update-cycle_id,
          owner         = @ls_update-owner,
          planned_start = @ls_update-planned_start,
          planned_end   = @ls_update-planned_end,
          due_date      = @ls_update-due_date,
          version       = @ls_update-version,
          changed_at    = @ls_update-changed_at,
          changed_by    = @ls_update-changed_by
      WHERE req_id = @ls_update-req_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Could not update request { ls_update-req_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'REQ'
                        iv_object_id   = CONV string( ls_update-req_id )
                        iv_action      = 'UPDATE' ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD change_status.
    DATA ls_current TYPE zcrw_req.
    DATA ls_update  TYPE zcrw_req.

    ls_current = get( iv_req_id ).
    validate_transition( iv_from = ls_current-status iv_to = iv_status ).

    ls_update = ls_current.
    ls_update-status     = iv_status.
    ls_update-version    = bump_version( ls_current-version ).
    ls_update-changed_at = zcl_crw_util=>now( ).
    ls_update-changed_by = sy-uname.

    IF iv_status = gc_status_approved.
      ls_update-approval_state = gc_approval_ok.
    ELSEIF iv_status = gc_status_rejected.
      ls_update-approval_state = gc_approval_rej.
    ELSEIF iv_status = gc_status_closed.
      ls_update-closed_at = ls_update-changed_at.
    ENDIF.

    UPDATE zcrw_req
      SET status         = @ls_update-status,
          approval_state = @ls_update-approval_state,
          version        = @ls_update-version,
          changed_at     = @ls_update-changed_at,
          changed_by     = @ls_update-changed_by,
          closed_at      = @ls_update-closed_at
      WHERE req_id = @ls_update-req_id
        AND version = @ls_current-version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = |Could not change status of { iv_req_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'REQ'
                        iv_object_id   = CONV string( iv_req_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD action.
    lock_request( iv_req_id ).

    TRY.
        perform_action( iv_req_id  = iv_req_id
                        iv_action  = iv_action
                        iv_version = iv_version
                        iv_comment = iv_comment ).
        unlock_request( iv_req_id ).
      CATCH zcx_crw_error INTO DATA(lx_lock_error).
        unlock_request( iv_req_id ).
        RAISE EXCEPTION lx_lock_error.
      ENDTRY.
  ENDMETHOD.

  METHOD perform_action.
    DATA ls_current TYPE zcrw_req.
    DATA lt_roles TYPE zcl_crw_auth=>tt_roles.
    DATA lv_user TYPE string.
    DATA lv_target TYPE string.
    DATA lv_status TYPE zcrw_req-status.
    DATA lv_approval TYPE zcrw_req-approval_state.
    DATA lv_version TYPE zcrw_req-version.
    DATA lv_now TYPE char14.
    DATA lv_closed TYPE char14.
    DATA lv_reason TYPE zcrw_req-cancel_reason.
    DATA lv_appr_id TYPE string.
    DATA lv_steps TYPE i.
    DATA lv_cd_count TYPE i.

    lv_user = sy-uname.
    lt_roles = zcl_crw_auth=>load_roles( lv_user ).
    ls_current = get( iv_req_id ).

    IF ls_current-version <> iv_version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The change request was changed by another user'.
    ENDIF.

    lv_target = zcl_crw_workflow=>target_status( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                                 iv_from        = CONV string( ls_current-status )
                                                 iv_action      = iv_action ).
    IF lv_target IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION'
                  iv_text = |Current status { ls_current-status } does not allow { iv_action }|.
    ENDIF.

*   Role checks per action (ADMIN passes every check inside require_any).
    CASE iv_action.
      WHEN zcl_crw_workflow=>gc_act_submit.
        IF lv_user <> ls_current-requester.
          zcl_crw_auth=>require_any( it_roles = lt_roles
                                     iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                     iv_action = iv_action ).
        ENDIF.
        check_submit_fields( ls_current ).
      WHEN zcl_crw_workflow=>gc_act_withdraw.
        IF lv_user <> ls_current-requester.
          zcl_crw_auth=>require_any( it_roles = lt_roles
                                     iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                     iv_action = iv_action ).
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_approve_step.
        lv_appr_id = zcl_crw_appr_svc=>current_step_for_user( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                                              iv_object_id   = CONV string( iv_req_id )
                                                              iv_user        = lv_user ).
        IF lv_appr_id IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'APPROVER_MISMATCH' iv_text = 'You are not the current approver'.
        ENDIF.
        zcl_crw_appr_svc=>decide( iv_appr_id  = lv_appr_id
                                  iv_user     = lv_user
                                  iv_decision = zcl_crw_appr_svc=>gc_state_approved
                                  iv_comment  = iv_comment
                                  iv_version  = iv_version ).
        RETURN.
      WHEN zcl_crw_workflow=>gc_act_reject.
        lv_appr_id = zcl_crw_appr_svc=>current_step_for_user( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                                              iv_object_id   = CONV string( iv_req_id )
                                                              iv_user        = lv_user ).
        IF lv_appr_id IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'APPROVER_MISMATCH' iv_text = 'You are not the current approver'.
        ENDIF.
        zcl_crw_appr_svc=>decide( iv_appr_id  = lv_appr_id
                                  iv_user     = lv_user
                                  iv_decision = zcl_crw_appr_svc=>gc_state_rejected
                                  iv_comment  = iv_comment
                                  iv_version  = iv_version ).
        RETURN.
      WHEN zcl_crw_workflow=>gc_act_skip_step.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        zcl_crw_appr_svc=>skip_step( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                     iv_object_id   = CONV string( iv_req_id )
                                     iv_user        = lv_user ).
        RETURN.
      WHEN zcl_crw_workflow=>gc_act_revise.
        IF lv_user <> ls_current-requester.
          zcl_crw_auth=>require_any( it_roles = lt_roles
                                     iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                     iv_action = iv_action ).
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_start_progress.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager )
                                                                  ( zcl_crw_auth=>gc_developer ) )
                                   iv_action = iv_action ).
        SELECT COUNT(*) FROM zcrw_cd WHERE req_id = @iv_req_id INTO @lv_cd_count.
        IF lv_cd_count = 0.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'GUARD_FAILED' iv_text = 'At least one change document is required'.
        ENDIF.
      WHEN zcl_crw_workflow=>gc_act_close.
        zcl_crw_auth=>require_any( it_roles = lt_roles
                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                   iv_action = iv_action ).
        check_close_guard( iv_req_id ).
      WHEN zcl_crw_workflow=>gc_act_cancel.
        IF iv_comment IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'A cancel reason is required'.
        ENDIF.
        IF strlen( iv_comment ) > 80.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'A cancel reason must not exceed 80 characters'.
        ENDIF.
        IF ls_current-status = gc_status_new AND lv_user = ls_current-requester.
          " The requester may cancel the own draft.
        ELSE.
          zcl_crw_auth=>require_any( it_roles = lt_roles
                                     iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager ) )
                                     iv_action = iv_action ).
        ENDIF.
    ENDCASE.

*   Submit generates the approval steps before the status update.
    lv_approval = ls_current-approval_state.
    IF iv_action = zcl_crw_workflow=>gc_act_submit.
      lv_steps = zcl_crw_appr_svc=>generate_steps( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                                   iv_object_id   = CONV string( iv_req_id )
                                                   iv_req_type    = CONV string( ls_current-req_type )
                                                   iv_priority    = CONV string( ls_current-priority ) ).
      IF lv_steps = 0.
        lv_target = gc_status_approved.
        lv_approval = gc_approval_ok.
      ELSE.
        lv_approval = gc_approval_pending.
      ENDIF.
    ELSEIF iv_action = zcl_crw_workflow=>gc_act_withdraw
        OR iv_action = zcl_crw_workflow=>gc_act_revise.
      lv_approval = gc_approval_none.
      zcl_crw_appr_svc=>skip_pending( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                      iv_object_id   = CONV string( iv_req_id )
                                      iv_action      = iv_action ).
    ELSEIF iv_action = zcl_crw_workflow=>gc_act_cancel.
      IF lv_approval = gc_approval_pending.
        lv_approval = gc_approval_skipped.
      ENDIF.
      zcl_crw_appr_svc=>skip_pending( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                      iv_object_id   = CONV string( iv_req_id )
                                      iv_action      = iv_action ).
    ENDIF.

    lv_status = lv_target.
    lv_version = bump_version( ls_current-version ).
    lv_now = zcl_crw_util=>now( ).
    lv_closed = ls_current-closed_at.
    lv_reason = ls_current-cancel_reason.

    IF lv_target = gc_status_closed OR lv_target = gc_status_cancelled.
      lv_closed = lv_now.
    ENDIF.
    IF lv_target = gc_status_cancelled.
      lv_reason = iv_comment.
    ENDIF.

    UPDATE zcrw_req
      SET status         = @lv_status,
          approval_state = @lv_approval,
          version        = @lv_version,
          changed_at     = @lv_now,
          changed_by     = @sy-uname,
          closed_at      = @lv_closed,
          cancel_reason  = @lv_reason
      WHERE req_id = @iv_req_id
        AND version = @iv_version.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The change request was changed by another user'.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'REQ'
                        iv_object_id   = CONV string( iv_req_id )
                        iv_action      = iv_action
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( lv_status )
                        iv_comment     = iv_comment ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD notes_add.
    DATA ls_note TYPE zcrw_note.

    IF iv_text IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Note text is required'.
    ENDIF.
    IF strlen( iv_text ) > 255.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Note text must not exceed 255 characters'.
    ENDIF.

    get( iv_req_id ).

    ls_note-note_id     = zcl_crw_util=>uuid( ).
    ls_note-object_type = 'REQ'.
    ls_note-object_id   = iv_req_id.
    ls_note-author      = sy-uname.
    ls_note-text        = iv_text.
    ls_note-created_at  = zcl_crw_util=>now( ).
    ls_note-visibility  = iv_visibility.

    INSERT zcrw_note FROM ls_note.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOTE_INSERT' iv_text = 'Could not create the note'.
    ENDIF.

    COMMIT WORK AND WAIT.
    rv_note_id = ls_note-note_id.
  ENDMETHOD.

  METHOD notes_list.
    DATA lv_object_type TYPE string.

    lv_object_type = 'REQ'.

    SELECT *
      FROM zcrw_note
      WHERE object_type = @lv_object_type
        AND object_id   = @iv_req_id
      ORDER BY created_at DESCENDING
      INTO TABLE @rt_notes.
  ENDMETHOD.

  METHOD display_id.
    rv_display_id = |{ gc_display_prefix }-{ iv_req_id }|.
  ENDMETHOD.

  METHOD next_id.
    DATA lv_number TYPE inri-nr.

    lv_number = zcl_crw_number=>next( 'ZCRW_REQ' ).
    rv_req_id = zcl_crw_util=>number_id( lv_number ).
  ENDMETHOD.

  METHOD validate_transition.
    IF zcl_crw_workflow=>is_valid( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                    iv_from        = CONV string( iv_from )
                                    iv_action      = COND string( WHEN iv_to = zcl_crw_workflow=>gc_req_pending THEN zcl_crw_workflow=>gc_act_submit
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_req_approved THEN zcl_crw_workflow=>gc_act_approve_step
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_req_rejected THEN zcl_crw_workflow=>gc_act_reject
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_req_progress THEN zcl_crw_workflow=>gc_act_start_progress
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_req_closed THEN zcl_crw_workflow=>gc_act_close
                                                                   WHEN iv_to = zcl_crw_workflow=>gc_req_cancelled THEN zcl_crw_workflow=>gc_act_cancel
                                                                   ELSE zcl_crw_workflow=>gc_act_submit ) ) = abap_false.
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

  METHOD check_submit_fields.
    IF is_request-title IS INITIAL
        OR is_request-priority IS INITIAL
        OR is_request-component IS INITIAL
        OR is_request-planned_start IS INITIAL
        OR is_request-planned_end IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR'
                  iv_text = 'Title, priority, component and planned dates are required'.
    ENDIF.
  ENDMETHOD.

  METHOD check_close_guard.
    DATA lv_open TYPE i.
    DATA lv_closed TYPE zcrw_cd-status.
    DATA lv_cancelled TYPE zcrw_cd-status.

    lv_closed = zcl_crw_workflow=>gc_cd_closed.
    lv_cancelled = zcl_crw_workflow=>gc_cd_cancelled.

    SELECT COUNT(*)
      FROM zcrw_cd
      WHERE req_id = @iv_req_id
        AND status <> @lv_closed
        AND status <> @lv_cancelled
      INTO @lv_open.

    IF lv_open > 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'GUARD_FAILED'
                  iv_text = |{ lv_open } change document(s) are still open|.
    ENDIF.
  ENDMETHOD.
  METHOD lock_request.
    CALL FUNCTION 'ENQUEUE_EZCRW_REQ'
      EXPORTING
        req_id        = iv_req_id
      EXCEPTIONS
        foreign_lock  = 1
        system_failure = 2
        OTHERS        = 3.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'OBJECT_LOCKED'
                  iv_text = 'The change request is locked by another user'.
    ENDIF.
  ENDMETHOD.

  METHOD unlock_request.
    CALL FUNCTION 'DEQUEUE_EZCRW_REQ'
      EXPORTING
        req_id = iv_req_id.
  ENDMETHOD.

ENDCLASS.
