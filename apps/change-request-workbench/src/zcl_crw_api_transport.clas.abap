CLASS zcl_crw_api_transport DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             cd_id   TYPE string,
             trkorr  TYPE string,
             tr_kind TYPE string,
             task_id TYPE string,
             reason  TYPE string,
           END OF ty_body.

    CLASS-METHODS list_transports
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_transport
      IMPORTING io_ctx   TYPE REF TO zcl_crw_api_context
                iv_trkorr TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS link_transport
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS unlink_transport
      IMPORTING io_ctx   TYPE REF TO zcl_crw_api_context
                iv_trkorr TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS detach_transport
      IMPORTING io_ctx   TYPE REF TO zcl_crw_api_context
                iv_trkorr TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS sync_transports
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS read_body
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rs_body) TYPE ty_body.

    CLASS-METHODS page_params
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      EXPORTING ev_page TYPE i
                ev_size TYPE i.

    CLASS-METHODS slice_count
      IMPORTING iv_total       TYPE i
                iv_page        TYPE i
                iv_size        TYPE i
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS detail
      IMPORTING is_row       TYPE zcrw_tr
                it_objects   TYPE zcl_crw_api_types=>tt_transport_objects
                iv_degraded  TYPE abap_bool
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_transport_detail.
ENDCLASS.

CLASS zcl_crw_api_transport IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 2.
      IF io_ctx->mv_method <> 'GET'.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed'.
      ENDIF.
      list_transports( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lv_id = 'link'.
      link_transport( io_ctx ).
      RETURN.
    ENDIF.
    IF lv_id = 'sync'.
      sync_transports( io_ctx ).
      RETURN.
    ENDIF.

    IF lines( it_segments ) = 2 AND io_ctx->mv_method = 'GET'.
      get_transport( io_ctx = io_ctx iv_trkorr = lv_id ).
      RETURN.
    ENDIF.

    IF lines( it_segments ) >= 3.
      lv_sub = it_segments[ 3 ].
      CASE lv_sub.
        WHEN 'unlink'.
          unlink_transport( io_ctx = io_ctx iv_trkorr = lv_id ).
        WHEN 'mark-detached'.
          detach_transport( io_ctx = io_ctx iv_trkorr = lv_id ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown transport action { lv_sub }|.
      ENDCASE.
      RETURN.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_crw_error
      EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown transport path'.
  ENDMETHOD.

  METHOD list_transports.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_transport_svc=>tt_transports.
    DATA lt_dto TYPE STANDARD TABLE OF zcl_crw_api_types=>ty_transport WITH EMPTY KEY.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).

    lt_rows = zcl_crw_transport_svc=>list( iv_cd_id     = CONV zcrw_tr-cd_id( io_ctx->param( 'cdId' ) )
                                            iv_tr_kind    = CONV zcrw_tr-tr_kind( io_ctx->param( 'trKind' ) )
                                            iv_target_sys = CONV zcrw_tr-tarsystem( io_ctx->param( 'targetSystem' ) )
                                            iv_sync_state = CONV zcrw_tr-sync_state( io_ctx->param( 'syncState' ) )
                                            iv_query      = io_ctx->param( 'q' ) ).

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>transport( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD get_transport.
    DATA ls_row TYPE zcrw_tr.
    DATA lt_objects TYPE zcl_crw_api_types=>tt_transport_objects.
    DATA lv_degraded TYPE abap_bool.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_transport_detail.

    ls_row = zcl_crw_transport_svc=>get( CONV e070-trkorr( iv_trkorr ) ).

    TRY.
        lt_objects = zcl_crw_transport_svc=>objects( CONV e070-trkorr( iv_trkorr ) ).
      CATCH zcx_crw_error.
        lv_degraded = abap_true.
    ENDTRY.

    ls_dto = detail( is_row = ls_row it_objects = lt_objects iv_degraded = lv_degraded ).
    io_ctx->set_data( ls_dto ).
  ENDMETHOD.

  METHOD link_transport.
    DATA ls_body TYPE ty_body.
    DATA ls_row TYPE zcrw_tr.

    ls_body = read_body( io_ctx ).
    IF ls_body-cd_id IS INITIAL OR ls_body-trkorr IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'cdId and trkorr are required'.
    ENDIF.
    IF ls_body-tr_kind IS INITIAL.
      ls_body-tr_kind = zcl_crw_transport_svc=>gc_kind_dev.
    ENDIF.

    zcl_crw_transport_svc=>link( iv_cd_id   = CONV zcrw_cd-cd_id( ls_body-cd_id )
                                  iv_trkorr  = CONV e070-trkorr( ls_body-trkorr )
                                  iv_tr_kind = to_upper( ls_body-tr_kind )
                                  iv_task_id = CONV zcrw_tr-task_id( ls_body-task_id ) ).

    ls_row = zcl_crw_transport_svc=>get( CONV e070-trkorr( ls_body-trkorr ) ).
    io_ctx->set_status( 201 ).
    io_ctx->set_data( zcl_crw_api_map=>transport( ls_row ) ).
  ENDMETHOD.

  METHOD unlink_transport.
    DATA ls_row TYPE zcrw_tr.

    zcl_crw_transport_svc=>unlink( CONV e070-trkorr( iv_trkorr ) ).
    ls_row = zcl_crw_transport_svc=>get( CONV e070-trkorr( iv_trkorr ) ).
    io_ctx->set_data( zcl_crw_api_map=>transport( ls_row ) ).
  ENDMETHOD.

  METHOD detach_transport.
    DATA ls_body TYPE ty_body.
    DATA ls_row TYPE zcrw_tr.

    ls_body = read_body( io_ctx ).
    zcl_crw_transport_svc=>mark_detached( iv_trkorr = CONV e070-trkorr( iv_trkorr )
                                           iv_reason  = ls_body-reason ).
    ls_row = zcl_crw_transport_svc=>get( CONV e070-trkorr( iv_trkorr ) ).
    io_ctx->set_data( zcl_crw_api_map=>transport( ls_row ) ).
  ENDMETHOD.

  METHOD sync_transports.
    DATA ls_body TYPE ty_body.
    DATA lv_synced TYPE i.
    DATA lv_json TYPE string.

    ls_body = read_body( io_ctx ).
    lv_synced = zcl_crw_transport_svc=>sync( CONV e070-trkorr( ls_body-trkorr ) ).

    lv_json = |\{"synced":{ lv_synced }\}|.
    io_ctx->set_json( lv_json ).
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

  METHOD detail.
    rs_dto-trkorr              = is_row-trkorr.
    rs_dto-cd_id               = is_row-cd_id.
    rs_dto-task_id             = is_row-task_id.
    rs_dto-tr_kind             = is_row-tr_kind.
    rs_dto-target_system       = is_row-tarsystem.
    rs_dto-tr_status           = is_row-tr_status.
    rs_dto-tr_status_text      = is_row-tr_status_txt.
    rs_dto-released_at         = zcl_crw_json=>format_timestamp( is_row-released_at ).
    rs_dto-import_scheduled_at = zcl_crw_json=>format_timestamp( is_row-import_scheduled_at ).
    rs_dto-imported_at         = zcl_crw_json=>format_timestamp( is_row-imported_at ).
    rs_dto-last_sync_at        = zcl_crw_json=>format_timestamp( is_row-last_sync_at ).
    rs_dto-linked_at           = zcl_crw_json=>format_timestamp( is_row-linked_at ).
    rs_dto-linked_by           = is_row-linked_by.
    rs_dto-retrofit_state      = is_row-retrofit_state.
    rs_dto-sync_state          = is_row-sync_state.
    rs_dto-description         = is_row-description.
    rs_dto-linked              = xsdbool( is_row-cd_id IS NOT INITIAL ).
    rs_dto-degraded            = iv_degraded.
    rs_dto-objects             = it_objects.
  ENDMETHOD.
ENDCLASS.
