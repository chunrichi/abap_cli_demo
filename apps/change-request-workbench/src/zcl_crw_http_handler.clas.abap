CLASS zcl_crw_http_handler DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.
    CONSTANTS: gc_mime_root TYPE string VALUE '/zcrw',
               gc_index     TYPE string VALUE 'index.html',
               gc_api       TYPE string VALUE '/api/v1'.

    METHODS serve_static
      IMPORTING io_server TYPE REF TO if_http_server
                iv_path   TYPE string.

    METHODS read_mime
      IMPORTING iv_path           TYPE string
      RETURNING VALUE(rv_content) TYPE xstring.

    METHODS mime_type
      IMPORTING iv_path        TYPE string
      RETURNING VALUE(rv_type) TYPE string.

    METHODS respond_json
      IMPORTING io_server TYPE REF TO if_http_server
                iv_status TYPE i
                iv_json   TYPE string.
ENDCLASS.

CLASS zcl_crw_http_handler IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    DATA lv_path TYPE string.
    DATA lv_method TYPE string.

    lv_path = server->request->get_header_field( '~path_info' ).
    lv_method = server->request->get_method( ).

    IF lv_path CP |{ gc_api }*|.
      zcl_crw_api_router=>handle( io_server = server ).
      RETURN.
    ENDIF.

    IF lv_method <> 'GET'.
      respond_json( io_server = server
                    iv_status = 405
                    iv_json   = `{"status":"error","message":"method not allowed"}` ).
      RETURN.
    ENDIF.

    serve_static( io_server = server iv_path = lv_path ).
  ENDMETHOD.

  METHOD serve_static.
    DATA lv_file TYPE string.
    DATA lv_content TYPE xstring.
    DATA lv_mime TYPE string.
    DATA lv_index TYPE xstring.

    IF iv_path IS INITIAL OR iv_path = '/'.
      lv_file = gc_index.
    ELSE.
      lv_file = iv_path.
    ENDIF.

    IF iv_path = '/favicon.ico'.
      io_server->response->set_status( code = 204 reason = 'No Content' ).
      RETURN.
    ENDIF.

    lv_content = read_mime( lv_file ).
    IF lv_content IS INITIAL AND iv_path <> '/' AND iv_path <> '' AND iv_path <> '/index.html'.
      IF iv_path CP '*.*'.
*       A missing asset is a real 404, not a SPA route.
        respond_json( io_server = io_server
                      iv_status = 404
                      iv_json   = `{"status":"error","message":"asset not found"}` ).
        RETURN.
      ENDIF.
*     SPA fallback: deep links and refresh resolve to the single entry document.
      lv_file = gc_index.
      lv_content = read_mime( lv_file ).
    ENDIF.

    IF lv_content IS INITIAL.
      lv_index = read_mime( gc_index ).
      IF lv_index IS INITIAL.
        respond_json( io_server = io_server
                      iv_status = 500
                      iv_json   = `{"status":"error","message":"index document is missing"}` ).
        RETURN.
      ENDIF.
      lv_file = gc_index.
      lv_content = lv_index.
    ENDIF.

    lv_mime = mime_type( lv_file ).

    io_server->response->set_status( code = 200 reason = 'OK' ).
    io_server->response->set_header_field( name = 'Content-Type' value = |{ lv_mime }; charset=utf-8| ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-cache' ).
    io_server->response->set_header_field( name = 'X-Content-Type-Options' value = 'nosniff' ).
    io_server->response->set_header_field( name = 'Content-Security-Policy'
                                            value = `default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'` ).
    io_server->response->set_data( data = lv_content ).
  ENDMETHOD.

  METHOD read_mime.
    DATA lv_content TYPE xstring.
    DATA lv_mime TYPE string.
    DATA lv_url TYPE string.

    lv_url = |{ gc_mime_root }/{ iv_path }|.

    TRY.
        DATA(lr_api) = cl_mime_repository_api=>if_mr_api~get_api( ).
        CALL METHOD lr_api->get
          EXPORTING
            i_url       = lv_url
          IMPORTING
            e_content   = lv_content
            e_mime_type = lv_mime
          EXCEPTIONS
            parameter_missing  = 1
            error_occured      = 2
            not_found          = 3
            permission_failure = 4
            OTHERS             = 5.
        IF sy-subrc <> 0.
          CLEAR rv_content.
          RETURN.
        ENDIF.
      CATCH cx_root.
        CLEAR rv_content.
        RETURN.
    ENDTRY.

    rv_content = lv_content.
  ENDMETHOD.

  METHOD mime_type.
    IF iv_path CP '*.html'.
      rv_type = 'text/html'.
    ELSEIF iv_path CP '*.css'.
      rv_type = 'text/css'.
    ELSEIF iv_path CP '*.js' OR iv_path CP '*.mjs'.
      rv_type = 'application/javascript'.
    ELSEIF iv_path CP '*.json'.
      rv_type = 'application/json'.
    ELSEIF iv_path CP '*.svg'.
      rv_type = 'image/svg+xml'.
    ELSEIF iv_path CP '*.png'.
      rv_type = 'image/png'.
    ELSEIF iv_path CP '*.jpg' OR iv_path CP '*.jpeg'.
      rv_type = 'image/jpeg'.
    ELSE.
      rv_type = 'application/octet-stream'.
    ENDIF.
  ENDMETHOD.

  METHOD respond_json.
    io_server->response->set_status( code = iv_status reason = 'Error' ).
    io_server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    io_server->response->set_cdata( data = iv_json ).
  ENDMETHOD.
ENDCLASS.
