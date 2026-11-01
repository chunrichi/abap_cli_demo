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
               gc_approval_pending TYPE zcrw_cd-approval_state VALUE 'PENDING',
               gc_display_prefix   TYPE string VALUE 'CD'.

    CLASS-METHODS create
      IMPORTING is_input TYPE ty_create_input
      RETURNING VALUE(rv_cd_id) TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_cd_id TYPE zcrw_cd-cd_id
      RETURNING VALUE(rs_document) TYPE zcrw_cd
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_req_id TYPE zcrw_cd-req_id OPTIONAL
                iv_status TYPE zcrw_cd-status OPTIONAL
      RETURNING VALUE(rt_documents) TYPE tt_documents.

    CLASS-METHODS update
      IMPORTING is_document TYPE zcrw_cd
      RAISING   zcx_crw_error.

    CLASS-METHODS change_status
      IMPORTING iv_cd_id  TYPE zcrw_cd-cd_id
                iv_status TYPE zcrw_cd-status
      RAISING   zcx_crw_error.

    CLASS-METHODS display_id
      IMPORTING iv_cd_id TYPE zcrw_cd-cd_id
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
      IMPORTING iv_version TYPE zcrw_cd-version
      RETURNING VALUE(rv_version) TYPE zcrw_cd-version.
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
    ls_document-approval_state    = gc_approval_pending.
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
  ENDMETHOD.

  METHOD update.
    DATA ls_current TYPE zcrw_cd.
    DATA ls_update  TYPE zcrw_cd.

    ls_current = get( is_document-cd_id ).
    IF ls_current-version <> is_document-version.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_VERSION_CONFLICT' iv_text = |Change document { is_document-cd_id } was changed by another user|.
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

    UPDATE zcrw_cd FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_UPDATE' iv_text = |Could not update change document { ls_update-cd_id }|.
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

    UPDATE zcrw_cd FROM ls_update.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CD_STATUS_UPDATE' iv_text = |Could not change status of { iv_cd_id }|.
    ENDIF.

    zcl_crw_audit=>log( iv_object_type = 'CD'
                        iv_object_id   = CONV string( iv_cd_id )
                        iv_action      = 'STATUS'
                        iv_field       = 'STATUS'
                        iv_old_value   = CONV string( ls_current-status )
                        iv_new_value   = CONV string( iv_status ) ).
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
    CASE iv_from.
      WHEN gc_status_new.
        IF iv_to <> gc_status_dev AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_dev.
        IF iv_to <> gc_status_test AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_test.
        IF iv_to <> gc_status_ready AND iv_to <> gc_status_dev AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_ready.
        IF iv_to <> gc_status_scheduled AND iv_to <> gc_status_imported AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_scheduled.
        IF iv_to <> gc_status_imported AND iv_to <> gc_status_cancelled.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN gc_status_imported.
        IF iv_to <> gc_status_closed.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'CD_TRANSITION' iv_text = |Invalid transition { iv_from } -> { iv_to }|.
        ENDIF.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CD_TERMINAL' iv_text = |Change document is already closed or cancelled|.
    ENDCASE.
  ENDMETHOD.

  METHOD bump_version.
    DATA lv_version TYPE i.

    lv_version = iv_version.
    lv_version = lv_version + 1.
    rv_version = lv_version.
  ENDMETHOD.
ENDCLASS.
