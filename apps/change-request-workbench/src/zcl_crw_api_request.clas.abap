CLASS zcl_crw_api_request DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             request_type      TYPE string,
             title             TYPE string,
             description       TYPE string,
             priority          TYPE string,
             component         TYPE string,
             cycle_id          TYPE string,
             owner             TYPE string,
             planned_start     TYPE string,
             planned_end       TYPE string,
             due_date          TYPE string,
             version           TYPE i,
             action            TYPE string,
             comment           TYPE string,
             text              TYPE string,
             visibility        TYPE string,
             target_system     TYPE string,
             dev_lead          TYPE string,
             test_lead         TYPE string,
             planned_import_at TYPE string,
           END OF ty_body.

    TYPES: BEGIN OF ty_created,
             id         TYPE string,
             display_id TYPE string,
             status     TYPE string,
             version    TYPE i,
           END OF ty_created.

    CONSTANTS: gc_sort_created TYPE string VALUE 'created_at',
               gc_sort_changed TYPE string VALUE 'changed_at',
               gc_sort_id      TYPE string VALUE 'req_id',
               gc_sort_title   TYPE string VALUE 'title',
               gc_sort_status  TYPE string VALUE 'status',
               gc_sort_prio    TYPE string VALUE 'priority',
               gc_sort_due     TYPE string VALUE 'due_date'.

    CLASS-METHODS list_requests
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS create_request
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_request
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS patch_request
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS action_request
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_change_documents
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS create_change_document
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_history
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_notes
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS create_note
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_req_id TYPE zcrw_req-req_id
      RAISING   zcx_crw_error.

    CLASS-METHODS read_body
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rs_body) TYPE ty_body.

    CLASS-METHODS page_params
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      EXPORTING ev_page TYPE i
                ev_size TYPE i.

    CLASS-METHODS sort_field
      IMPORTING iv_sort        TYPE string
      RETURNING VALUE(rv_field) TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS is_limited
      IMPORTING io_ctx          TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rv_limited) TYPE abap_bool.

    CLASS-METHODS slice_count
      IMPORTING iv_total      TYPE i
                iv_page       TYPE i
                iv_size       TYPE i
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS validate_text
      IMPORTING iv_text TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS detail_json
      IMPORTING io_ctx        TYPE REF TO zcl_crw_api_context
                is_dto        TYPE zcl_crw_api_types=>ty_request
                it_cds        TYPE zcl_crw_api_types=>tt_cds
                it_actions    TYPE string_table
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_api_request IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_resource TYPE string.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 1.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = it_segments[ 1 ].
    IF lv_resource <> 'requests'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDIF.

    IF lines( it_segments ) = 1.
      CASE io_ctx->mv_method.
        WHEN 'GET'.
          list_requests( io_ctx ).
        WHEN 'POST'.
          create_request( io_ctx ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /requests'.
      ENDCASE.
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lines( it_segments ) = 2.
      CASE io_ctx->mv_method.
        WHEN 'GET'.
          get_request( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
        WHEN 'PATCH'.
          patch_request( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /requests/{id}'.
      ENDCASE.
      RETURN.
    ENDIF.

    lv_sub = it_segments[ 3 ].
    CASE lv_sub.
      WHEN 'actions'.
        IF io_ctx->mv_method <> 'POST'.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Actions require POST'.
        ENDIF.
        action_request( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
      WHEN 'change-documents'.
        CASE io_ctx->mv_method.
          WHEN 'GET'.
            list_change_documents( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
          WHEN 'POST'.
            create_change_document( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for change documents'.
        ENDCASE.
      WHEN 'history'.
        list_history( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
      WHEN 'notes'.
        CASE io_ctx->mv_method.
          WHEN 'GET'.
            list_notes( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
          WHEN 'POST'.
            create_note( io_ctx = io_ctx iv_req_id = CONV zcrw_req-req_id( lv_id ) ).
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for notes'.
        ENDCASE.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown sub resource { lv_sub }|.
    ENDCASE.
  ENDMETHOD.

  METHOD list_requests.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_sort TYPE string.
    DATA lv_order TYPE string.
    DATA lv_field TYPE string.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_requester TYPE zcrw_req-requester.
    DATA lt_rows TYPE zcl_crw_request_svc=>tt_requests.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_requests.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).

    lv_sort = io_ctx->param( 'sort' ).
    IF lv_sort IS INITIAL.
      lv_sort = 'createdAt'.
    ENDIF.
    lv_field = sort_field( lv_sort ).

    lv_order = to_lower( io_ctx->param( 'order' ) ).
    IF lv_order <> 'asc'.
      lv_order = 'desc'.
    ENDIF.

    IF is_limited( io_ctx ) = abap_true.
      lv_requester = io_ctx->mv_user.
    ELSE.
      lv_requester = io_ctx->param( 'requester' ).
    ENDIF.

    lt_rows = zcl_crw_request_svc=>list( iv_status       = CONV zcrw_req-status( io_ctx->param( 'status' ) )
                                         iv_owner        = CONV zcrw_req-owner( io_ctx->param( 'owner' ) )
                                         iv_requester    = lv_requester
                                         iv_request_type = CONV zcrw_req-req_type( io_ctx->param( 'requestType' ) )
                                         iv_priority     = CONV zcrw_req-priority( io_ctx->param( 'priority' ) )
                                         iv_component    = CONV zcrw_req-component( io_ctx->param( 'component' ) )
                                         iv_cycle_id     = CONV zcrw_req-cycle_id( io_ctx->param( 'cycleId' ) )
                                         iv_query        = io_ctx->param( 'q' ) ).

    IF lv_order = 'asc'.
      SORT lt_rows BY (lv_field) ASCENDING.
    ELSE.
      SORT lt_rows BY (lv_field) DESCENDING.
    ENDIF.

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).

    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>request( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items     = lt_dto
                       iv_page      = lv_page
                       iv_page_size = lv_size
                       iv_total     = lv_total ).
  ENDMETHOD.

  METHOD create_request.
    DATA ls_body TYPE ty_body.
    DATA ls_input TYPE zcl_crw_request_svc=>ty_create_input.
    DATA ls_created TYPE ty_created.

    ls_body = read_body( io_ctx ).
    validate_text( ls_body-title ).
    validate_text( ls_body-description ).

    ls_input-req_type = ls_body-request_type.
    ls_input-title = ls_body-title.
    ls_input-description = ls_body-description.
    ls_input-priority = ls_body-priority.
    ls_input-component = ls_body-component.
    ls_input-cycle_id = ls_body-cycle_id.
    ls_input-owner = ls_body-owner.
    ls_input-planned_start = zcl_crw_json=>parse_date( ls_body-planned_start ).
    ls_input-planned_end = zcl_crw_json=>parse_date( ls_body-planned_end ).
    ls_input-due_date = zcl_crw_json=>parse_date( ls_body-due_date ).

    ls_created-id = zcl_crw_request_svc=>create( ls_input ).
    ls_created-display_id = zcl_crw_request_svc=>display_id( CONV zcrw_req-req_id( ls_created-id ) ).
    ls_created-status = zcl_crw_request_svc=>gc_status_new.
    ls_created-version = 1.

    io_ctx->set_status( 201 ).
    io_ctx->set_data( ls_created ).
  ENDMETHOD.

  METHOD get_request.
    DATA ls_row TYPE zcrw_req.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_request.
    DATA lt_cds TYPE zcl_crw_cd_svc=>tt_documents.
    DATA lt_cd_dto TYPE zcl_crw_api_types=>tt_cds.
    DATA lt_actions TYPE string_table.

    ls_row = zcl_crw_request_svc=>get( iv_req_id ).
    ls_dto = zcl_crw_api_map=>request( ls_row ).
    lt_cds = zcl_crw_cd_svc=>list( iv_req_id = iv_req_id ).
    LOOP AT lt_cds ASSIGNING FIELD-SYMBOL(<ls_cd>).
      APPEND zcl_crw_api_map=>change_document( <ls_cd> ) TO lt_cd_dto.
    ENDLOOP.
    lt_actions = zcl_crw_workflow=>allowed_actions( iv_object_type = zcl_crw_workflow=>gc_obj_req
                                                    iv_status      = CONV string( ls_row-status ) ).

    detail_json( io_ctx = io_ctx is_dto = ls_dto it_cds = lt_cd_dto it_actions = lt_actions ).
  ENDMETHOD.

  METHOD patch_request.
    DATA ls_body TYPE ty_body.
    DATA ls_current TYPE zcrw_req.
    DATA ls_update TYPE zcrw_req.

    ls_body = read_body( io_ctx ).
    IF ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'version is required'.
    ENDIF.

    ls_current = zcl_crw_request_svc=>get( iv_req_id ).
    ls_update = ls_current.
    ls_update-version = ls_body-version.

    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'title' ).
      validate_text( ls_body-title ).
      ls_update-title = ls_body-title.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'description' ).
      validate_text( ls_body-description ).
      ls_update-description = ls_body-description.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'priority' ).
      ls_update-priority = ls_body-priority.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'component' ).
      ls_update-component = ls_body-component.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'cycleId' ).
      ls_update-cycle_id = ls_body-cycle_id.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'owner' ).
      ls_update-owner = ls_body-owner.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'plannedStart' ).
      ls_update-planned_start = zcl_crw_json=>parse_date( ls_body-planned_start ).
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'plannedEnd' ).
      ls_update-planned_end = zcl_crw_json=>parse_date( ls_body-planned_end ).
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'dueDate' ).
      ls_update-due_date = zcl_crw_json=>parse_date( ls_body-due_date ).
    ENDIF.

    zcl_crw_request_svc=>update( ls_update ).

    io_ctx->set_data( zcl_crw_api_map=>request( zcl_crw_request_svc=>get( iv_req_id ) ) ).
  ENDMETHOD.

  METHOD action_request.
    DATA ls_body TYPE ty_body.

    ls_body = read_body( io_ctx ).
    IF ls_body-action IS INITIAL OR ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'action and version are required'.
    ENDIF.

    zcl_crw_request_svc=>action( iv_req_id  = iv_req_id
                                 iv_action  = to_upper( ls_body-action )
                                 iv_version = ls_body-version
                                 iv_comment = ls_body-comment ).

    io_ctx->set_data( zcl_crw_api_map=>request( zcl_crw_request_svc=>get( iv_req_id ) ) ).
  ENDMETHOD.

  METHOD list_change_documents.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_cd_svc=>tt_documents.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_cds.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    lt_rows = zcl_crw_cd_svc=>list( iv_req_id = iv_req_id ).

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>change_document( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD create_change_document.
    DATA ls_body TYPE ty_body.
    DATA ls_input TYPE zcl_crw_cd_svc=>ty_create_input.
    DATA ls_parent TYPE zcrw_req.

    ls_body = read_body( io_ctx ).
    validate_text( ls_body-title ).

    IF ls_body-version > 0.
      ls_parent = zcl_crw_request_svc=>get( iv_req_id ).
      IF CONV i( ls_parent-version ) <> ls_body-version.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CONCURRENT_MODIFICATION' iv_text = 'The change request was changed by another user'.
      ENDIF.
    ENDIF.

    ls_input-req_id = iv_req_id.
    ls_input-title = ls_body-title.
    ls_input-cycle_id = ls_body-cycle_id.
    ls_input-target_sys = ls_body-target_system.
    ls_input-owner = ls_body-owner.
    ls_input-dev_lead = ls_body-dev_lead.
    ls_input-test_lead = ls_body-test_lead.
    ls_input-planned_import_at = zcl_crw_json=>parse_timestamp( ls_body-planned_import_at ).

    DATA(lv_cd_id) = zcl_crw_cd_svc=>create( ls_input ).

    io_ctx->set_status( 201 ).
    io_ctx->set_data( zcl_crw_api_map=>change_document( zcl_crw_cd_svc=>get( lv_cd_id ) ) ).
  ENDMETHOD.

  METHOD list_history.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_total TYPE i.
    DATA lt_rows TYPE zcl_crw_audit=>tt_history.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_history.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    lv_offset = ( lv_page - 1 ) * lv_size.

    lv_total = zcl_crw_audit=>count( iv_object_type = 'REQ' iv_object_id = CONV string( iv_req_id ) ).
    lt_rows = zcl_crw_audit=>list( iv_object_type = 'REQ'
                                   iv_object_id   = CONV string( iv_req_id )
                                   iv_offset      = lv_offset
                                   iv_size        = lv_size ).
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND zcl_crw_api_map=>history( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD list_notes.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_request_svc=>tt_notes.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_notes.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    lt_rows = zcl_crw_request_svc=>notes_list( iv_req_id ).
    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>note( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD create_note.
    DATA ls_body TYPE ty_body.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_note.

    ls_body = read_body( io_ctx ).
    DATA(lv_note_id) = zcl_crw_request_svc=>notes_add( iv_req_id = iv_req_id
                                                       iv_text   = ls_body-text
                                                       iv_visibility = ls_body-visibility ).

    ls_dto-id = lv_note_id.
    ls_dto-object_type = 'REQ'.
    ls_dto-object_id = iv_req_id.
    ls_dto-author = io_ctx->mv_user.
    ls_dto-text = ls_body-text.
    ls_dto-created_at = zcl_crw_json=>format_timestamp( zcl_crw_util=>now( ) ).
    ls_dto-visibility = COND #( WHEN ls_body-visibility IS INITIAL THEN 'PUBLIC' ELSE ls_body-visibility ).

    io_ctx->set_status( 201 ).
    io_ctx->set_data( ls_dto ).
  ENDMETHOD.

  METHOD read_body.
    zcl_crw_json=>deserialize( EXPORTING iv_json = io_ctx->mv_body CHANGING cs_data = rs_body ).
  ENDMETHOD.

  METHOD page_params.
    ev_page = io_ctx->param_int( iv_name = 'page' iv_default = 1 ).
    IF ev_page < 1.
      ev_page = 1.
    ENDIF.
    ev_size = io_ctx->param_int( iv_name = 'size' iv_default = 50 ).
    IF ev_size < 1.
      ev_size = 50.
    ENDIF.
    IF ev_size > 200.
      ev_size = 200.
    ENDIF.
  ENDMETHOD.

  METHOD sort_field.
    CASE iv_sort.
      WHEN 'createdAt'.
        rv_field = gc_sort_created.
      WHEN 'changedAt'.
        rv_field = gc_sort_changed.
      WHEN 'id'.
        rv_field = gc_sort_id.
      WHEN 'title'.
        rv_field = gc_sort_title.
      WHEN 'status'.
        rv_field = gc_sort_status.
      WHEN 'priority'.
        rv_field = gc_sort_prio.
      WHEN 'dueDate'.
        rv_field = gc_sort_due.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = |Unsupported sort field { iv_sort }|.
    ENDCASE.
  ENDMETHOD.

  METHOD is_limited.
    DATA lv_unrestricted TYPE abap_bool.

    IF zcl_crw_auth=>is_admin( io_ctx->mt_roles ) = abap_true.
      RETURN.
    ENDIF.

    lv_unrestricted = zcl_crw_auth=>has_any_role( it_roles = io_ctx->mt_roles
                                                   iv_roles = VALUE string_table( ( zcl_crw_auth=>gc_change_manager )
                                                                                  ( zcl_crw_auth=>gc_developer )
                                                                                  ( zcl_crw_auth=>gc_tester )
                                                                                  ( zcl_crw_auth=>gc_release_manager ) ) ).
    rv_limited = xsdbool( lv_unrestricted = abap_false ).
  ENDMETHOD.

  METHOD slice_count.
    DATA lv_rest TYPE i.

    IF iv_page < 1 OR iv_size < 1.
      rv_count = 0.
      RETURN.
    ENDIF.

    lv_rest = iv_total - ( iv_page - 1 ) * iv_size.
    IF lv_rest <= 0.
      rv_count = 0.
    ELSE.
      rv_count = nmin( val1 = iv_size val2 = lv_rest ).
    ENDIF.
  ENDMETHOD.

  METHOD validate_text.
    IF strlen( iv_text ) > 255.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Text must not exceed 255 characters'.
    ENDIF.
  ENDMETHOD.

  METHOD detail_json.
    DATA lv_base TYPE string.
    DATA lv_length TYPE i.
    DATA lv_json TYPE string.

    lv_base = zcl_crw_json=>serialize( is_dto ).
    lv_length = strlen( lv_base ).
    IF lv_length > 1.
      lv_base = substring( val = lv_base len = lv_length - 1 ).
    ENDIF.

    lv_json = lv_base && ',"changeDocuments":' && zcl_crw_json=>serialize( it_cds ) &&
              ',"allowedActions":' && zcl_crw_json=>serialize( it_actions ) && '}'.

    io_ctx->set_json( lv_json ).
  ENDMETHOD.
ENDCLASS.
