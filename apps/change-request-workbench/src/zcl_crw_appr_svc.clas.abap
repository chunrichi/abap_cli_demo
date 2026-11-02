CLASS zcl_crw_appr_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_approvals TYPE STANDARD TABLE OF zcrw_appr WITH EMPTY KEY.

    CONSTANTS: gc_state_pending  TYPE string VALUE 'PENDING',
               gc_state_approved TYPE string VALUE 'APPROVED',
               gc_state_rejected TYPE string VALUE 'REJECTED',
               gc_state_skipped  TYPE string VALUE 'SKIPPED',
               gc_obj_req        TYPE string VALUE 'REQ',
               gc_obj_cd         TYPE string VALUE 'CD'.

    CLASS-METHODS generate_steps
      IMPORTING iv_object_type  TYPE string
                iv_object_id    TYPE string
                iv_req_type     TYPE string
                iv_priority     TYPE string
      RETURNING VALUE(rv_steps) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS has_pending
      IMPORTING iv_object_type    TYPE string
                iv_object_id      TYPE string
      RETURNING VALUE(rv_pending) TYPE abap_bool.

    CLASS-METHODS current_step
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_step) TYPE i.

    CLASS-METHODS decide
      IMPORTING iv_appr_id            TYPE string
                iv_user               TYPE string
                iv_decision           TYPE string
                iv_comment            TYPE string
                iv_version            TYPE i
      RETURNING VALUE(rv_all_approved) TYPE abap_bool
      RAISING   zcx_crw_error.

    CLASS-METHODS reassign
      IMPORTING iv_appr_id      TYPE string
                iv_user         TYPE string
                iv_new_approver TYPE string
                iv_comment      TYPE string DEFAULT ''
      RETURNING VALUE(rs_step)  TYPE zcrw_appr
      RAISING   zcx_crw_error.

    CLASS-METHODS skip_step
      IMPORTING iv_object_type        TYPE string
                iv_object_id          TYPE string
                iv_user               TYPE string
      RETURNING VALUE(rv_all_approved) TYPE abap_bool
      RAISING   zcx_crw_error.

    CLASS-METHODS skip_pending
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_action      TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS list_for_user
      IMPORTING iv_user        TYPE string
                iv_scope       TYPE string
      RETURNING VALUE(rt_rows) TYPE tt_approvals.

    CLASS-METHODS get_step
      IMPORTING iv_appr_id     TYPE string
      RETURNING VALUE(rs_step) TYPE zcrw_appr
      RAISING   zcx_crw_error.

    CLASS-METHODS current_step_for_user
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_user        TYPE string
      RETURNING VALUE(rv_appr_id) TYPE string.

    CLASS-METHODS steps_for_object
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rt_rows) TYPE tt_approvals.

    CLASS-METHODS object_title
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_title) TYPE string.

    CLASS-METHODS object_display_id
      IMPORTING iv_object_type  TYPE string
                iv_object_id    TYPE string
      RETURNING VALUE(rv_id)    TYPE string.

    CLASS-METHODS object_version
      IMPORTING iv_object_type    TYPE string
                iv_object_id      TYPE string
      RETURNING VALUE(rv_version) TYPE i
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CLASS-METHODS resolve_users
      IMPORTING iv_role         TYPE string
                iv_user         TYPE string
      RETURNING VALUE(rt_users) TYPE string_table.

    CLASS-METHODS object_requester
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_user) TYPE string.

    CLASS-METHODS current_step_mandatory
      IMPORTING iv_object_type     TYPE string
                iv_object_id       TYPE string
      RETURNING VALUE(rv_mandatory) TYPE string.

    CLASS-METHODS count_pending_steps
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS finalize_object
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_approved    TYPE abap_bool
                iv_version     TYPE i
                iv_comment     TYPE string
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_appr_svc IMPLEMENTATION.
  METHOD generate_steps.
    DATA lt_cfg TYPE STANDARD TABLE OF zcrw_appr_cfg WITH EMPTY KEY.
    DATA lt_rows TYPE tt_approvals.

    SELECT *
      FROM zcrw_appr_cfg
      WHERE object_type = @iv_object_type
        AND ( req_type = @iv_req_type OR req_type = '' )
        AND ( priority = @iv_priority OR priority = '' )
      ORDER BY step_no ASCENDING
      INTO TABLE @lt_cfg.

    LOOP AT lt_cfg ASSIGNING FIELD-SYMBOL(<ls_cfg>).
      DATA(lt_users) = resolve_users( iv_role = CONV string( <ls_cfg>-approver_role )
                                      iv_user = CONV string( <ls_cfg>-approver_user ) ).
      IF lt_users IS INITIAL.
        APPEND VALUE #( appr_id     = zcl_crw_util=>uuid( )
                        object_type = iv_object_type
                        object_id   = iv_object_id
                        step_no     = <ls_cfg>-step_no
                        approver    = ''
                        appr_state  = gc_state_skipped
                        created_at  = zcl_crw_util=>now( ) ) TO lt_rows.
        CONTINUE.
      ENDIF.

      LOOP AT lt_users ASSIGNING FIELD-SYMBOL(<lv_user>).
        APPEND VALUE #( appr_id     = zcl_crw_util=>uuid( )
                        object_type = iv_object_type
                        object_id   = iv_object_id
                        step_no     = <ls_cfg>-step_no
                        approver    = <lv_user>
                        appr_state  = gc_state_pending
                        created_at  = zcl_crw_util=>now( ) ) TO lt_rows.
        rv_steps = rv_steps + 1.
      ENDLOOP.
    ENDLOOP.

    IF lt_rows IS NOT INITIAL.
      INSERT zcrw_appr FROM TABLE @lt_rows.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING
            iv_code = 'APPR_INSERT'
            iv_text = 'Could not create approval steps'.
      ENDIF.
    ENDIF.

*   Notify each approver that a pending step was assigned.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_pending>) WHERE appr_state = gc_state_pending.
      IF <ls_pending>-approver IS NOT INITIAL.
        zcl_crw_notify=>notify_approval_pending( <ls_pending> ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD has_pending.
    rv_pending = xsdbool( count_pending_steps( iv_object_type = iv_object_type
                                               iv_object_id   = iv_object_id ) > 0 ).
  ENDMETHOD.

  METHOD current_step.
    DATA lv_step TYPE zcrw_appr-step_no.

    SELECT MIN( step_no )
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND appr_state  = @gc_state_pending
      INTO @lv_step.

    rv_step = lv_step.
  ENDMETHOD.

  METHOD decide.
    DATA lt_steps TYPE tt_approvals.
    DATA lv_step TYPE i.
    DATA lv_version TYPE i.
    DATA lv_now TYPE char14.
    DATA lv_object_type TYPE string.
    DATA lv_object_id TYPE string.

    SELECT SINGLE *
      FROM zcrw_appr
      WHERE appr_id = @iv_appr_id
      INTO @DATA(ls_step).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'APPR_NOT_FOUND'
          iv_text = |Approval step { iv_appr_id } not found|.
    ENDIF.

    lv_object_type = CONV string( ls_step-object_type ).
    lv_object_id = CONV string( ls_step-object_id ).

    IF ls_step-appr_state <> gc_state_pending.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'INVALID_TRANSITION'
          iv_text = |Approval step { iv_appr_id } is already decided|.
    ENDIF.

    IF ls_step-approver IS NOT INITIAL AND ls_step-approver <> iv_user.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'APPROVER_MISMATCH'
          iv_text = 'Only the current approver can decide this step'.
    ENDIF.

    IF object_requester( iv_object_type = lv_object_type
                         iv_object_id   = lv_object_id ) = iv_user.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'SELF_APPROVAL'
          iv_text = 'The requester cannot approve the own change request'.
    ENDIF.

    IF iv_decision <> gc_state_approved AND iv_decision <> gc_state_rejected.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'VALIDATION_ERROR'
          iv_text = 'Decision must be APPROVED or REJECTED'.
    ENDIF.

    IF iv_decision = gc_state_rejected AND iv_comment IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'VALIDATION_ERROR'
          iv_text = 'A rejection comment is required'.
    ENDIF.

    lv_version = object_version( iv_object_type = lv_object_type
                                 iv_object_id   = lv_object_id ).
    IF lv_version <> iv_version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'CONCURRENT_MODIFICATION'
          iv_text = 'The object was changed by another user'.
    ENDIF.

    lv_step = ls_step-step_no.
    lv_now = zcl_crw_util=>now( ).

    SELECT *
      FROM zcrw_appr
      WHERE object_type = @lv_object_type
        AND object_id   = @lv_object_id
        AND step_no     = @lv_step
      INTO TABLE @lt_steps.

*   ANY rule: decide one row, skip the remaining rows of the same step.
    LOOP AT lt_steps ASSIGNING FIELD-SYMBOL(<ls_row>).
      IF <ls_row>-appr_id = iv_appr_id.
        UPDATE zcrw_appr
          SET appr_state  = @iv_decision,
              decided_at  = @lv_now,
              comment_txt = @iv_comment
          WHERE appr_id = @iv_appr_id.
        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING
              iv_code = 'APPR_UPDATE'
              iv_text = 'Could not update the approval step'.
        ENDIF.
      ELSE.
        UPDATE zcrw_appr
          SET appr_state = @gc_state_skipped,
              decided_at = @lv_now
          WHERE appr_id = @<ls_row>-appr_id.
      ENDIF.
    ENDLOOP.

    IF iv_decision = gc_state_rejected.
*     Rejection terminates the whole approval flow for this object.
      LOOP AT lt_steps ASSIGNING <ls_row> WHERE appr_state = gc_state_pending.
        IF <ls_row>-appr_id = iv_appr_id.
          CONTINUE.
        ENDIF.
        UPDATE zcrw_appr
          SET appr_state = @gc_state_skipped,
              decided_at = @lv_now
          WHERE appr_id = @<ls_row>-appr_id.
      ENDLOOP.
      zcl_crw_notify=>notify_approval_rejected( iv_object_type = lv_object_type
                                                iv_object_id   = lv_object_id
                                                iv_appr_id     = iv_appr_id
                                                iv_comment     = iv_comment ).

      finalize_object( iv_object_type = lv_object_type
                       iv_object_id   = lv_object_id
                       iv_approved    = abap_false
                       iv_version     = iv_version
                       iv_comment     = iv_comment ).
      RETURN.
    ENDIF.

    rv_all_approved = xsdbool( count_pending_steps( iv_object_type = lv_object_type
                                                     iv_object_id   = lv_object_id ) = 0 ).
    IF rv_all_approved = abap_true.
      finalize_object( iv_object_type = lv_object_type
                       iv_object_id   = lv_object_id
                       iv_approved    = abap_true
                       iv_version     = iv_version
                       iv_comment     = iv_comment ).
    ELSE.
      zcl_crw_audit=>log( iv_object_type = lv_object_type
                          iv_object_id   = lv_object_id
                          iv_action      = 'APPROVE_STEP'
                          iv_comment     = iv_comment ).
    ENDIF.
  ENDMETHOD.

  METHOD reassign.
    DATA ls_step TYPE zcrw_appr.
    DATA lv_old_approver TYPE zcrw_appr-approver.
    DATA lv_now TYPE char14.
    DATA lt_roles TYPE zcl_crw_auth=>tt_roles.
    DATA lt_allowed TYPE string_table.

    IF iv_appr_id IS INITIAL OR iv_user IS INITIAL OR iv_new_approver IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR'
                  iv_text = 'Approval id, actor and new approver are required'.
    ENDIF.
    IF strlen( iv_new_approver ) > 12.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR'
                  iv_text = 'The approver id must not exceed 12 characters'.
    ENDIF.

    SELECT SINGLE * FROM zcrw_appr WHERE appr_id = @iv_appr_id INTO @ls_step.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'APPR_NOT_FOUND' iv_text = |Approval step { iv_appr_id } not found|.
    ENDIF.

    IF ls_step-appr_state <> gc_state_pending.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = 'Only a pending step can be reassigned'.
    ENDIF.

*   The current approver may reassign the step; change managers and admins may do it as well.
    IF ls_step-approver <> iv_user.
      lt_roles = zcl_crw_auth=>load_roles( iv_user = iv_user ).
      lt_allowed = VALUE #( ( zcl_crw_auth=>gc_change_manager ) ( zcl_crw_auth=>gc_admin ) ).
      IF zcl_crw_auth=>has_any_role( it_roles = lt_roles iv_roles = lt_allowed ) = abap_false.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'FORBIDDEN' iv_text = 'Only the current approver or a change manager can reassign'.
      ENDIF.
    ENDIF.

    IF iv_new_approver = ls_step-approver.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'The new approver is identical to the current approver'.
    ENDIF.

    IF object_requester( iv_object_type = CONV string( ls_step-object_type )
                         iv_object_id   = CONV string( ls_step-object_id ) ) = iv_new_approver.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'SELF_APPROVAL' iv_text = 'The requester cannot approve the own change request'.
    ENDIF.

    lv_old_approver = ls_step-approver.
    lv_now = zcl_crw_util=>now( ).

    UPDATE zcrw_appr
      SET approver = @iv_new_approver
      WHERE appr_id = @iv_appr_id.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'APPR_UPDATE' iv_text = 'Could not reassign the approval step'.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = CONV string( ls_step-object_type )
                        iv_object_id   = CONV string( ls_step-object_id )
                        iv_action      = 'REASSIGN'
                        iv_field       = 'APPROVER'
                        iv_old_value   = CONV string( lv_old_approver )
                        iv_new_value   = iv_new_approver
                        iv_comment     = iv_comment ).

*   Notify the new approver and mark the previous approver notification as read.
    ls_step-approver = iv_new_approver.
    zcl_crw_notify=>notify_approval_pending( ls_step ).
    zcl_crw_notify=>mark_dedup_read( iv_user      = CONV string( lv_old_approver )
                                     iv_dedup_key = |APPR:{ iv_appr_id }| ).

    COMMIT WORK AND WAIT.

    SELECT SINGLE * FROM zcrw_appr WHERE appr_id = @iv_appr_id INTO @rs_step.
  ENDMETHOD.

  METHOD skip_step.
    DATA lv_step TYPE i.
    DATA lv_mandatory TYPE string.
    DATA lv_version TYPE i.
    DATA lv_now TYPE char14.
    DATA lt_steps TYPE tt_approvals.

    lv_now = zcl_crw_util=>now( ).

    lv_step = current_step( iv_object_type = iv_object_type iv_object_id = iv_object_id ).
    IF lv_step = 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'INVALID_TRANSITION'
          iv_text = 'There is no pending approval step'.
    ENDIF.

    lv_mandatory = current_step_mandatory( iv_object_type = iv_object_type
                                           iv_object_id   = iv_object_id ).
    IF lv_mandatory = 'X'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'GUARD_FAILED'
          iv_text = 'A mandatory approval step cannot be skipped'.
    ENDIF.

    SELECT *
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND step_no     = @lv_step
        AND appr_state  = @gc_state_pending
      INTO TABLE @lt_steps.

    LOOP AT lt_steps ASSIGNING FIELD-SYMBOL(<ls_step>).
      UPDATE zcrw_appr
        SET appr_state = @gc_state_skipped,
            decided_at = @lv_now
        WHERE appr_id = @<ls_step>-appr_id.
    ENDLOOP.

    zcl_crw_audit=>log( iv_object_type = iv_object_type
                        iv_object_id   = iv_object_id
                        iv_action      = 'SKIP_STEP'
                        iv_comment     = 'Approval step skipped' ).

    rv_all_approved = xsdbool( count_pending_steps( iv_object_type = iv_object_type
                                                     iv_object_id   = iv_object_id ) = 0 ).
    IF rv_all_approved = abap_true.
      lv_version = object_version( iv_object_type = iv_object_type
                                   iv_object_id   = iv_object_id ).
      finalize_object( iv_object_type = iv_object_type
                       iv_object_id   = iv_object_id
                       iv_approved    = abap_true
                       iv_version     = lv_version
                       iv_comment     = 'All approval steps skipped' ).
    ENDIF.
  ENDMETHOD.

  METHOD skip_pending.
    DATA lt_steps TYPE tt_approvals.
    DATA lv_now TYPE char14.

    lv_now = zcl_crw_util=>now( ).

    SELECT *
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND appr_state  = @gc_state_pending
      INTO TABLE @lt_steps.

    LOOP AT lt_steps ASSIGNING FIELD-SYMBOL(<ls_step>).
      UPDATE zcrw_appr
        SET appr_state = @gc_state_skipped,
            decided_at = @lv_now
        WHERE appr_id = @<ls_step>-appr_id.
    ENDLOOP.

    IF lt_steps IS NOT INITIAL AND iv_action IS NOT INITIAL.
      zcl_crw_audit=>log( iv_object_type = iv_object_type
                          iv_object_id   = iv_object_id
                          iv_action      = iv_action
                          iv_comment     = 'Pending approval steps were skipped' ).
    ENDIF.
  ENDMETHOD.

  METHOD list_for_user.
    DATA lt_rows TYPE tt_approvals.

    IF iv_scope = 'decided'.
      SELECT *
        FROM zcrw_appr
        WHERE approver   = @iv_user
          AND appr_state <> @gc_state_pending
        ORDER BY created_at DESCENDING
        INTO TABLE @rt_rows.
      RETURN.
    ENDIF.

    IF iv_scope = 'all'.
      SELECT *
        FROM zcrw_appr
        WHERE appr_state = @gc_state_pending
        ORDER BY created_at DESCENDING
        INTO TABLE @lt_rows.
    ELSE.
      SELECT *
        FROM zcrw_appr
        WHERE approver   = @iv_user
          AND appr_state = @gc_state_pending
        ORDER BY created_at DESCENDING
        INTO TABLE @lt_rows.
    ENDIF.

*   Only the current step of each object is actionable.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      IF current_step( iv_object_type = CONV string( <ls_row>-object_type )
                       iv_object_id   = CONV string( <ls_row>-object_id ) ) = <ls_row>-step_no.
        APPEND <ls_row> TO rt_rows.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_step.
    SELECT SINGLE *
      FROM zcrw_appr
      WHERE appr_id = @iv_appr_id
      INTO @rs_step.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'APPR_NOT_FOUND' iv_text = |Approval step { iv_appr_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD current_step_for_user.
    DATA lv_step TYPE zcrw_appr-step_no.

    lv_step = current_step( iv_object_type = iv_object_type iv_object_id = iv_object_id ).
    IF lv_step = 0.
      RETURN.
    ENDIF.

    SELECT SINGLE appr_id
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND step_no     = @lv_step
        AND approver    = @iv_user
        AND appr_state  = @gc_state_pending
      INTO @rv_appr_id.
  ENDMETHOD.

  METHOD steps_for_object.
    SELECT *
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
      ORDER BY step_no ASCENDING, approver ASCENDING
      INTO TABLE @rt_rows.
  ENDMETHOD.

  METHOD object_title.
    IF iv_object_type = gc_obj_req.
      SELECT SINGLE title FROM zcrw_req WHERE req_id = @iv_object_id INTO @rv_title.
    ELSEIF iv_object_type = gc_obj_cd.
      SELECT SINGLE title FROM zcrw_cd WHERE cd_id = @iv_object_id INTO @rv_title.
    ENDIF.
  ENDMETHOD.

  METHOD object_display_id.
    IF iv_object_type = gc_obj_req.
      rv_id = zcl_crw_request_svc=>display_id( CONV zcrw_req-req_id( iv_object_id ) ).
    ELSEIF iv_object_type = gc_obj_cd.
      rv_id = zcl_crw_cd_svc=>display_id( CONV zcrw_cd-cd_id( iv_object_id ) ).
    ENDIF.
  ENDMETHOD.

  METHOD object_version.
    DATA lv_numc TYPE zcrw_req-version.

    IF iv_object_type = gc_obj_req.
      SELECT SINGLE version FROM zcrw_req WHERE req_id = @iv_object_id INTO @lv_numc.
    ELSEIF iv_object_type = gc_obj_cd.
      SELECT SINGLE version FROM zcrw_cd WHERE cd_id = @iv_object_id INTO @lv_numc.
    ENDIF.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = COND #( WHEN iv_object_type = gc_obj_req THEN 'CR_NOT_FOUND' ELSE 'CD_NOT_FOUND' )
          iv_text = 'Object not found'.
    ENDIF.

    rv_version = lv_numc.
  ENDMETHOD.

  METHOD resolve_users.
    IF iv_user IS NOT INITIAL.
      APPEND iv_user TO rt_users.
      RETURN.
    ENDIF.

    IF iv_role IS NOT INITIAL.
      rt_users = zcl_crw_auth=>role_members( iv_role ).
    ENDIF.
  ENDMETHOD.

  METHOD object_requester.
    DATA lv_req_id TYPE zcrw_cd-req_id.

    IF iv_object_type = gc_obj_req.
      SELECT SINGLE requester FROM zcrw_req WHERE req_id = @iv_object_id INTO @rv_user.
    ELSEIF iv_object_type = gc_obj_cd.
      SELECT SINGLE req_id FROM zcrw_cd WHERE cd_id = @iv_object_id INTO @lv_req_id.
      SELECT SINGLE requester FROM zcrw_req WHERE req_id = @lv_req_id INTO @rv_user.
    ENDIF.
  ENDMETHOD.

  METHOD current_step_mandatory.
    DATA lv_step TYPE i.
    DATA lv_req_type TYPE string.
    DATA lv_priority TYPE string.

    lv_step = current_step( iv_object_type = iv_object_type iv_object_id = iv_object_id ).
    IF iv_object_type = gc_obj_req.
      SELECT SINGLE req_type, priority FROM zcrw_req
        WHERE req_id = @iv_object_id INTO (@lv_req_type, @lv_priority).
    ELSEIF iv_object_type = gc_obj_cd.
      lv_req_type = 'STD'.
      SELECT SINGLE r~priority
        FROM zcrw_req AS r
        INNER JOIN zcrw_cd AS c ON r~req_id = c~req_id
        WHERE c~cd_id = @iv_object_id
        INTO @lv_priority.
    ENDIF.

    SELECT SINGLE mandatory
      FROM zcrw_appr_cfg
      WHERE object_type = @iv_object_type
        AND step_no     = @lv_step
        AND ( req_type = @lv_req_type OR req_type = '' )
        AND ( priority = @lv_priority OR priority = '' )
      INTO @rv_mandatory.
  ENDMETHOD.

  METHOD count_pending_steps.
    SELECT COUNT(*)
      FROM zcrw_appr
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND appr_state  = @gc_state_pending
      INTO @rv_count.
  ENDMETHOD.

  METHOD finalize_object.
    DATA lv_now TYPE char14.
    DATA lv_version TYPE zcrw_req-version.
    DATA lv_action TYPE string.
    DATA lv_state TYPE string.

    lv_now = zcl_crw_util=>now( ).
    lv_version = iv_version + 1.

    IF iv_object_type = gc_obj_req.
      IF iv_approved = abap_true.
        lv_action = 'APPROVE_STEP'.
        lv_state = zcl_crw_workflow=>gc_req_approved.
        UPDATE zcrw_req
          SET status         = @lv_state,
              approval_state = @gc_state_approved,
              version        = @lv_version,
              changed_at     = @lv_now,
              changed_by     = @sy-uname
          WHERE req_id = @iv_object_id
            AND version = @iv_version.
      ELSE.
        lv_action = 'REJECT'.
        lv_state = zcl_crw_workflow=>gc_req_rejected.
        UPDATE zcrw_req
          SET status         = @lv_state,
              approval_state = @gc_state_rejected,
              version        = @lv_version,
              changed_at     = @lv_now,
              changed_by     = @sy-uname
          WHERE req_id = @iv_object_id
            AND version = @iv_version.
      ENDIF.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING
            iv_code = 'CONCURRENT_MODIFICATION'
            iv_text = 'The change request was changed by another user'.
      ENDIF.

      zcl_crw_audit=>log( iv_object_type = gc_obj_req
                          iv_object_id   = iv_object_id
                          iv_action      = lv_action
                          iv_field       = 'STATUS'
                          iv_new_value   = lv_state
                          iv_comment     = iv_comment ).
    ELSEIF iv_object_type = gc_obj_cd.
      lv_state = COND string( WHEN iv_approved = abap_true THEN gc_state_approved ELSE gc_state_rejected ).
      UPDATE zcrw_cd
        SET approval_state = @lv_state,
            version        = @lv_version,
            changed_at     = @lv_now,
            changed_by     = @sy-uname
        WHERE cd_id = @iv_object_id
          AND version = @iv_version.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING
            iv_code = 'CONCURRENT_MODIFICATION'
            iv_text = 'The change document was changed by another user'.
      ENDIF.

      zcl_crw_audit=>log( iv_object_type = gc_obj_cd
                          iv_object_id   = iv_object_id
                          iv_action      = COND #( WHEN iv_approved = abap_true THEN 'APPROVE_STEP' ELSE 'REJECT' )
                          iv_field       = 'APPROVAL_STATE'
                          iv_comment     = iv_comment ).
    ENDIF.

    COMMIT WORK AND WAIT.
  ENDMETHOD.
ENDCLASS.
