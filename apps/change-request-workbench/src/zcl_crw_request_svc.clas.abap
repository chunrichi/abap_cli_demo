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

    CONSTANTS: gc_status_new       TYPE zcrw_req-status VALUE 'NEW',
               gc_status_pending   TYPE zcrw_req-status VALUE 'PENDING_APPROVAL',
               gc_status_approved  TYPE zcrw_req-status VALUE 'APPROVED',
               gc_status_rejected  TYPE zcrw_req-status VALUE 'REJECTED',
               gc_status_progress  TYPE zcrw_req-status VALUE 'IN_PROGRESS',
               gc_status_closed    TYPE zcrw_req-status VALUE 'CLOSED',
               gc_status_cancelled TYPE zcrw_req-status VALUE 'CANCELLED',
               gc_approval_pending TYPE zcrw_req-approval_state VALUE 'PENDING',
               gc_approval_ok      TYPE zcrw_req-approval_state VALUE 'APPROVED',
               gc_approval_rej     TYPE zcrw_req-approval_state VALUE 'REJECTED',
               gc_display_prefix   TYPE string VALUE 'CR'.

    CLASS-METHODS create
      IMPORTING is_input TYPE ty_create_input
      RETURNING VALUE(rv_req_id) TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_req_id TYPE zcrw_req-req_id
      RETURNING VALUE(rs_request) TYPE zcrw_req
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_status    TYPE zcrw_req-status OPTIONAL
                iv_owner     TYPE zcrw_req-owner OPTIONAL
                iv_requester TYPE zcrw_req-requester OPTIONAL
      RETURNING VALUE(rt_requests) TYPE tt_requests.

    CLASS-METHODS update
      IMPORTING is_request TYPE zcrw_req
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_req_id TYPE zcrw_req-req_id
                iv_status TYPE zcrw_req-status
      RAISING   zcx_crw_error.

    CLASS-METHODS display_id
      IMPORTING iv_req_id TYPE zcrw_req-req_id
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
      IMPORTING iv_version TYPE zcrw_req-version
      RETURNING VALUE(rv_version) TYPE zcrw_req-version.
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
    ls_request-approval_state = gc_approval_pending.
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
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_req.
    DATA ls_update  TYPE zcrw_req.

    ls_current = get( is_request-req_id ).
    IF ls_current-version <> is_request-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_VERSION_CONFLICT' iv_text = |Request { is_request-req_id } was changed by another user|.
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

    UPDATE zcrw_req FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_UPDATE' iv_text = |Could not update request { ls_update-req_id }|.
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

    UPDATE zcrw_req FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CR_STATUS_UPDATE' iv_text = |Could not change status of { iv_req_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'REQ'
                        iv_object_id   = CONV string( iv_req_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
    COMMIT WORK AND WAIT.
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
    CASE iv_from.
      WHEN gc_status_new.
        IF iv_to <> gc_status_pending AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CR_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_pending.
        IF iv_to <> gc_status_approved AND iv_to <> gc_status_rejected.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CR_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_approved.
        IF iv_to <> gc_status_progress AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CR_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_progress.
        IF iv_to <> gc_status_closed AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CR_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_rejected.
        IF iv_to <> gc_status_pending AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CR_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CR_TERMINAL' iv_text = |Request is already closed or cancelled|.
    ENDCASE.
  ENDMETHOD.

  METHOD bump_version.
    DATA lv_version TYPE i.

    lv_version = iv_version.
    lv_version = lv_version + 1.
    rv_version = lv_version.
  ENDMETHOD.
ENDCLASS.
