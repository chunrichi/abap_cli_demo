CLASS zcl_crw_api_router DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS handle
      IMPORTING io_server TYPE REF TO if_http_server.

  PRIVATE SECTION.
    CLASS-METHODS parse_request
      IMPORTING io_server       TYPE REF TO if_http_server
      RETURNING VALUE(ro_ctx)   TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS dispatch
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS send_response
      IMPORTING io_server TYPE REF TO if_http_server
                io_ctx    TYPE REF TO zcl_crw_api_context.

    CLASS-METHODS send_error
      IMPORTING io_server        TYPE REF TO if_http_server
                iv_status        TYPE i
                iv_code          TYPE string
                iv_message       TYPE string
                iv_correlation   TYPE string.

    CLASS-METHODS api_error_code
      IMPORTING iv_internal_code TYPE string
      RETURNING VALUE(rv_code)   TYPE string.

    CLASS-METHODS http_status
      IMPORTING iv_code        TYPE string
      RETURNING VALUE(rv_status) TYPE i.

    CLASS-METHODS add_query_params
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                io_server TYPE REF TO if_http_server.

    CLASS-METHODS url_decode
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS zcl_crw_api_router IMPLEMENTATION.
  METHOD handle.
    DATA lo_ctx TYPE REF TO zcl_crw_api_context.
    DATA lv_correlation TYPE char32.

    lv_correlation = zcl_crw_util=>uuid( ).
    IF lv_correlation IS INITIAL.
      lv_correlation = 'unknown'.
    ENDIF.

    TRY.
        lo_ctx = parse_request( io_server ).
      CATCH zcx_crw_error INTO DATA(lx_parse).
        send_error( io_server      = io_server
                    iv_status      = 400
                    iv_code        = 'VALIDATION_ERROR'
                    iv_message     = lx_parse->mv_text
                    iv_correlation = CONV string( lv_correlation ) ).
        RETURN.
    ENDTRY.

    TRY.
        IF lo_ctx->mv_method <> 'GET'.
          IF io_server->request->get_header_field( 'X-CRW-Request' ) <> '1'.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR'
                        iv_text = 'The X-CRW-Request header is required for write requests'.
          ENDIF.
        ENDIF.

        dispatch( lo_ctx ).

        IF lo_ctx->mv_response IS INITIAL AND lo_ctx->mv_raw IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'NOT_FOUND' iv_text = |No handler for { lo_ctx->mv_method } { lo_ctx->mv_path }|.
        ENDIF.

        send_response( io_server = io_server io_ctx = lo_ctx ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        ROLLBACK WORK.
        DATA(lv_code) = api_error_code( lx_error->mv_code ).
        zcl_crw_log=>write_and_commit( iv_area           = 'API'
                                        iv_severity       = zcl_crw_log=>gc_sev_error
                                        iv_message        = |{ lo_ctx->mv_method } { lo_ctx->mv_path }: { lx_error->mv_code }| && | { lx_error->mv_text }|
                                        iv_context        = io_server->request->get_header_field( '~path_info' )
                                        iv_correlation_id = lo_ctx->mv_correlation_id ).
        send_error( io_server      = io_server
                    iv_status      = http_status( lv_code )
                    iv_code        = lv_code
                    iv_message     = COND #( WHEN lx_error->mv_text IS INITIAL THEN lv_code ELSE lx_error->mv_text )
                    iv_correlation = lo_ctx->mv_correlation_id ).
      CATCH cx_root INTO DATA(lx_root).
        ROLLBACK WORK.
        zcl_crw_log=>write_and_commit( iv_area           = 'API'
                                        iv_severity       = zcl_crw_log=>gc_sev_error
                                        iv_message        = |{ lo_ctx->mv_method } { lo_ctx->mv_path }: internal error|
                                        iv_context        = lx_root->get_text( )
                                        iv_correlation_id = lo_ctx->mv_correlation_id ).
        send_error( io_server      = io_server
                    iv_status      = 500
                    iv_code        = 'INTERNAL_ERROR'
                    iv_message     = 'Unexpected server error'
                    iv_correlation = lo_ctx->mv_correlation_id ).
    ENDTRY.
  ENDMETHOD.

  METHOD parse_request.
    DATA lv_path TYPE string.
    DATA lv_rest TYPE string.
    DATA lt_segments TYPE string_table.
    DATA lt_clean TYPE string_table.

    ro_ctx = NEW #( ).
    ro_ctx->mv_method = io_server->request->get_method( ).
    lv_path = io_server->request->get_header_field( '~path_info' ).
    ro_ctx->mv_path = lv_path.

    IF strlen( lv_path ) > 7.
      lv_rest = substring( val = lv_path off = 7 ).
    ENDIF.

    SPLIT lv_rest AT '/' INTO TABLE lt_segments.
    LOOP AT lt_segments ASSIGNING FIELD-SYMBOL(<lv_segment>).
      IF <lv_segment> IS NOT INITIAL.
        APPEND <lv_segment> TO lt_clean.
      ENDIF.
    ENDLOOP.

    CLEAR ro_ctx->mv_query.
    ro_ctx->mv_body = io_server->request->get_cdata( ).
    ro_ctx->mv_user = sy-uname.
    ro_ctx->mv_correlation_id = zcl_crw_util=>uuid( ).
    ro_ctx->mt_roles = zcl_crw_auth=>load_roles( ro_ctx->mv_user ).
    ro_ctx->mv_is_admin = zcl_crw_auth=>is_admin( ro_ctx->mt_roles ).

    add_query_params( io_ctx = ro_ctx io_server = io_server ).

*   The parsed segments are carried in the path field for the dispatcher.
    IF lt_clean IS NOT INITIAL.
      ro_ctx->mv_path = '/' && concat_lines_of( table = lt_clean sep = '/' ).
    ENDIF.

    ro_ctx->mv_status = 200.
  ENDMETHOD.

  METHOD dispatch.
    DATA lt_segments TYPE string_table.
    DATA lt_clean TYPE string_table.
    DATA lv_path TYPE string.
    DATA lv_resource TYPE string.

    lv_path = io_ctx->mv_path.
    SPLIT lv_path AT '/' INTO TABLE lt_segments.
    LOOP AT lt_segments ASSIGNING FIELD-SYMBOL(<lv_segment>).
      IF <lv_segment> IS NOT INITIAL.
        APPEND <lv_segment> TO lt_clean.
      ENDIF.
    ENDLOOP.

    IF lt_clean IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = lt_clean[ 1 ].

    CASE lv_resource.
      WHEN 'me' OR 'health' OR 'dashboard'.
        zcl_crw_api_me=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'requests'.
        zcl_crw_api_request=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'change-documents'.
        zcl_crw_api_cd=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'tasks'.
        zcl_crw_api_task=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'approvals'.
        zcl_crw_api_approval=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'transports'.
        zcl_crw_api_transport=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'schedules'.
        zcl_crw_api_schedule=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'reports'.
        zcl_crw_api_report=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN 'config'.
        zcl_crw_api_config=>dispatch( io_ctx = io_ctx it_segments = lt_clean ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDCASE.
  ENDMETHOD.

  METHOD send_response.
    io_server->response->set_status( code = io_ctx->mv_status reason = 'OK' ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    io_server->response->set_header_field( name = 'X-Content-Type-Options' value = 'nosniff' ).
    io_server->response->set_header_field( name = 'X-Correlation-ID' value = io_ctx->mv_correlation_id ).

    IF io_ctx->mv_is_raw = abap_true.
      io_server->response->set_header_field( name = 'Content-Type' value = io_ctx->mv_content_type ).
      io_server->response->set_data( data = io_ctx->mv_raw ).
    ELSEIF io_ctx->mv_is_text = abap_true.
      io_server->response->set_header_field( name = 'Content-Type' value = io_ctx->mv_content_type ).
      IF io_ctx->mv_content_disposition IS NOT INITIAL.
        io_server->response->set_header_field( name = 'Content-Disposition' value = io_ctx->mv_content_disposition ).
      ENDIF.
      io_server->response->set_cdata( data = io_ctx->mv_response ).
    ELSE.
      io_server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
      io_server->response->set_cdata( data = io_ctx->mv_response ).
    ENDIF.
  ENDMETHOD.

  METHOD send_error.
    DATA lv_reason TYPE string.
    DATA lv_body TYPE string.

    lv_reason = COND #( WHEN iv_status = 400 THEN 'Bad Request'
                        WHEN iv_status = 401 THEN 'Unauthorized'
                        WHEN iv_status = 403 THEN 'Forbidden'
                        WHEN iv_status = 404 THEN 'Not Found'
                        WHEN iv_status = 409 THEN 'Conflict'
                        WHEN iv_status = 502 THEN 'Bad Gateway'
                        ELSE 'Error' ).

    lv_body = |\{"status":"error","code":"{ zcl_crw_json=>escape( iv_code ) }"| &&
              |,"message":"{ zcl_crw_json=>escape( iv_message ) }"| &&
              |,"details":\{\},"correlationId":"{ iv_correlation }"\}|.

    io_server->response->set_status( code = iv_status reason = lv_reason ).
    io_server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    io_server->response->set_header_field( name = 'X-Content-Type-Options' value = 'nosniff' ).
    io_server->response->set_header_field( name = 'X-Correlation-ID' value = iv_correlation ).
    io_server->response->set_cdata( data = lv_body ).
  ENDMETHOD.

  METHOD api_error_code.
    CASE iv_internal_code.
      WHEN 'VALIDATION_ERROR' OR 'UNAUTHORIZED' OR 'FORBIDDEN'
        OR 'APPROVER_MISMATCH' OR 'SELF_APPROVAL'
        OR 'INVALID_TRANSITION' OR 'GUARD_FAILED'
        OR 'CONCURRENT_MODIFICATION' OR 'OBJECT_LOCKED'
        OR 'DUPLICATE_LINK' OR 'SCHEDULE_CONFLICT' OR 'CTS_READ_ERROR'.
        rv_code = iv_internal_code.
      WHEN 'NOT_FOUND' OR 'CR_NOT_FOUND' OR 'CD_NOT_FOUND' OR 'TASK_NOT_FOUND'
        OR 'TR_NOT_FOUND' OR 'SCHED_NOT_FOUND' OR 'APPR_NOT_FOUND'
        OR 'CD_REQ_NOT_FOUND' OR 'TASK_CD_NOT_FOUND'.
        rv_code = 'NOT_FOUND'.
      WHEN 'CR_TRANSITION' OR 'CD_TRANSITION' OR 'TASK_TRANSITION'
        OR 'CR_TERMINAL' OR 'CD_TERMINAL' OR 'TASK_TERMINAL'.
        rv_code = 'INVALID_TRANSITION'.
      WHEN 'CR_VERSION_CONFLICT' OR 'CD_VERSION_CONFLICT' OR 'TASK_VERSION_CONFLICT'.
        rv_code = 'CONCURRENT_MODIFICATION'.
      WHEN 'NR_INIT' OR 'NR_UPDATE' OR 'NR_CLOSE' OR 'NR_GET'.
        rv_code = 'NUMBER_RANGE_ERROR'.
      WHEN OTHERS.
        rv_code = COND #( WHEN iv_internal_code CP '*NOT_FOUND*' THEN 'NOT_FOUND'
                          WHEN iv_internal_code CP '*TRANSITION*' THEN 'INVALID_TRANSITION'
                          WHEN iv_internal_code CP '*VERSION*' THEN 'CONCURRENT_MODIFICATION'
                          WHEN iv_internal_code CP '*REQUIRED*' THEN 'VALIDATION_ERROR'
                          ELSE 'INTERNAL_ERROR' ).
    ENDCASE.
  ENDMETHOD.

  METHOD http_status.
    CASE iv_code.
      WHEN 'VALIDATION_ERROR'.
        rv_status = 400.
      WHEN 'UNAUTHORIZED'.
        rv_status = 401.
      WHEN 'FORBIDDEN' OR 'APPROVER_MISMATCH' OR 'SELF_APPROVAL'.
        rv_status = 403.
      WHEN 'NOT_FOUND'.
        rv_status = 404.
      WHEN 'INVALID_TRANSITION' OR 'GUARD_FAILED' OR 'CONCURRENT_MODIFICATION'
        OR 'OBJECT_LOCKED' OR 'DUPLICATE_LINK' OR 'SCHEDULE_CONFLICT'.
        rv_status = 409.
      WHEN 'CTS_READ_ERROR'.
        rv_status = 502.
      WHEN OTHERS.
        rv_status = 500.
    ENDCASE.
  ENDMETHOD.

  METHOD add_query_params.
    DATA lv_query TYPE string.
    DATA lt_pairs TYPE string_table.

    lv_query = io_server->request->get_header_field( '~query_string' ).
    IF lv_query IS INITIAL.
      RETURN.
    ENDIF.

    SPLIT lv_query AT '&' INTO TABLE lt_pairs.
    LOOP AT lt_pairs ASSIGNING FIELD-SYMBOL(<lv_pair>).
      DATA(lv_equals) = find( val = <lv_pair> sub = '=' ).
      IF lv_equals < 0.
        io_ctx->add_param( iv_name = url_decode( <lv_pair> ) iv_value = '' ).
      ELSE.
        DATA(lv_name) = substring( val = <lv_pair> len = lv_equals ).
        DATA(lv_value) = substring( val = <lv_pair> off = lv_equals + 1 ).
        io_ctx->add_param( iv_name  = url_decode( lv_name )
                           iv_value = url_decode( lv_value ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD url_decode.
    TRY.
        rv_text = cl_http_utility=>unescape_url( escaped = iv_text ).
      CATCH cx_root.
        rv_text = iv_text.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
