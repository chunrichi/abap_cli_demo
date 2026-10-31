CLASS zcl_dma_01_stats DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_extension.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
* ---------------------------------------------------------------------
* Types
* ---------------------------------------------------------------------
    TYPES: BEGIN OF ts_day_count,
             stat_date TYPE d,
             cnt       TYPE i,
           END OF ts_day_count,
           tt_day_count TYPE STANDARD TABLE OF ts_day_count WITH EMPTY KEY.

    TYPES: BEGIN OF ts_name_count,
             name TYPE string,
             cnt  TYPE i,
           END OF ts_name_count,
           tt_name_count TYPE STANDARD TABLE OF ts_name_count WITH EMPTY KEY.

    TYPES: BEGIN OF ts_series,
             date        TYPE d,
             user_ops    TYPE i,
             dev_objects TYPE i,
             transports  TYPE i,
           END OF ts_series,
           tt_series TYPE STANDARD TABLE OF ts_series WITH EMPTY KEY.

    TYPES: BEGIN OF ts_stats,
             days          TYPE i,
             from_date     TYPE d,
             to_date       TYPE d,
             generated_at  TYPE string,
             user_ops      TYPE i,
             active_users  TYPE i,
             dev_objects   TYPE i,
             transports    TYPE i,
             online_users  TYPE i,
             series        TYPE tt_series,
             top_tcodes    TYPE tt_name_count,
             top_obj_types TYPE tt_name_count,
           END OF ts_stats.

* ---------------------------------------------------------------------
* Constants
* ---------------------------------------------------------------------
    CONSTANTS: BEGIN OF gc_mime,
                 root  TYPE string VALUE '/zdma_01_stats',
                 index TYPE string VALUE 'index.html',
                 js    TYPE string VALUE 'app.js',
                 css   TYPE string VALUE 'styles.css',
               END OF gc_mime.
    CONSTANTS gc_default_days TYPE i VALUE 30.
    CONSTANTS gc_min_days     TYPE i VALUE 7.
    CONSTANTS gc_max_days     TYPE i VALUE 90.
    CONSTANTS gc_top_count    TYPE i VALUE 6.

* ---------------------------------------------------------------------
* Methods
* ---------------------------------------------------------------------
    METHODS build_stats
      IMPORTING iv_days         TYPE i
      RETURNING VALUE(rs_stats) TYPE ts_stats.

    METHODS to_json
      IMPORTING is_stats       TYPE ts_stats
      RETURNING VALUE(rv_json) TYPE string.

    METHODS to_json_name_list
      IMPORTING it_items       TYPE tt_name_count
      RETURNING VALUE(rv_json) TYPE string.

    METHODS escape_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    METHODS serve_mime
      IMPORTING io_server TYPE REF TO if_http_server
                iv_file   TYPE string.

    METHODS respond_json
      IMPORTING io_server TYPE REF TO if_http_server
                iv_status TYPE i
                iv_json   TYPE string.

    METHODS get_days
      IMPORTING iv_query       TYPE string
      RETURNING VALUE(rv_days) TYPE i.

    METHODS read_mime
      IMPORTING iv_file           TYPE string
      RETURNING VALUE(rv_content) TYPE xstring.

    METHODS get_top
      IMPORTING it_rows       TYPE tt_name_count
      RETURNING VALUE(rt_top) TYPE tt_name_count.
ENDCLASS.


CLASS zcl_dma_01_stats IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    " ICF entry point: dashboard page, MIME assets and JSON stats.
    DATA: lv_path   TYPE string,
          lv_query  TYPE string,
          lv_method TYPE string.

    lv_path   = server->request->get_header_field( '~path_info' ).
    lv_query  = server->request->get_header_field( '~query_string' ).
    lv_method = server->request->get_method( ).

    IF lv_method <> 'GET'.
      respond_json( io_server = server
                    iv_status = 405
                    iv_json   = `{"status":"error","message":"method not allowed"}` ).
      RETURN.
    ENDIF.

    IF lv_path = '/api/stats' OR lv_path = '/api/stats/'.
      DATA(lv_days) = get_days( lv_query ).
      respond_json( io_server = server
                    iv_status = 200
                    iv_json   = to_json( build_stats( lv_days ) ) ).
    ELSEIF lv_path IS INITIAL OR lv_path = '/' OR lv_path = '/index.html'.
      serve_mime( io_server = server iv_file = gc_mime-index ).
    ELSEIF lv_path = '/app.js'.
      serve_mime( io_server = server iv_file = gc_mime-js ).
    ELSEIF lv_path = '/styles.css'.
      serve_mime( io_server = server iv_file = gc_mime-css ).
    ELSEIF lv_path = '/favicon.ico'.
      server->response->set_status( code = 204 reason = 'No Content' ).
    ELSE.
      respond_json( io_server = server
                    iv_status = 404
                    iv_json   = `{"status":"error","message":"not found"}` ).
    ENDIF.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    " Classrun self-check for README verification.
    DATA(ls_stats) = build_stats( gc_default_days ).

*   Data layer self-check for README verification.
    out->write( |DMA_STATS_OK days={ ls_stats-days } userOps={ ls_stats-user_ops }| &&
                | devObjects={ ls_stats-dev_objects } transports={ ls_stats-transports }| &&
                | activeUsers={ ls_stats-active_users } onlineUsers={ ls_stats-online_users }| ).

*   MIME asset self-check for README verification.
    DATA(lt_assets) = VALUE string_table( ( gc_mime-index )
                                          ( gc_mime-js )
                                          ( gc_mime-css ) ).
    DATA(lv_mime_ok) = abap_true.
    LOOP AT lt_assets ASSIGNING FIELD-SYMBOL(<lv_asset>).
      IF read_mime( <lv_asset> ) IS INITIAL.
        lv_mime_ok = abap_false.
        out->write( |DMA_MIME_FAIL { <lv_asset> }| ).
      ENDIF.
    ENDLOOP.
    IF lv_mime_ok = abap_true.
      out->write( 'DMA_MIME_OK' ).
    ENDIF.

    out->write( to_json( ls_stats ) ).
  ENDMETHOD.

  METHOD build_stats.
    " Aggregate the last N days from CDHDR, VRSD, E070 and USR41.
    DATA: lv_from   TYPE d,
          lv_to     TYPE d,
          lv_offset TYPE i,
          lv_day    TYPE d,
          lv_online TYPE i.

    DATA: lt_user_ops    TYPE tt_day_count,
          lt_users       TYPE STANDARD TABLE OF cdhdr-username WITH EMPTY KEY,
          lt_tcodes      TYPE tt_name_count,
          lt_dev_objects TYPE tt_day_count,
          lt_obj_types   TYPE tt_name_count,
          lt_transports  TYPE tt_day_count.

    lv_to = sy-datum.
    lv_offset = iv_days - 1.
    lv_from = lv_to - lv_offset.

    rs_stats-days         = iv_days.
    rs_stats-from_date    = lv_from.
    rs_stats-to_date      = lv_to.
    rs_stats-generated_at = |{ sy-datum DATE = ISO } { sy-uzeit TIME = ISO }|.

*   User operations: change document entries per day.
    SELECT udate AS stat_date, COUNT(*) AS cnt
      FROM cdhdr
      INTO TABLE @lt_user_ops
      WHERE udate BETWEEN @lv_from AND @lv_to
      GROUP BY udate.

    SELECT DISTINCT username
      FROM cdhdr
      INTO TABLE @lt_users
      WHERE udate BETWEEN @lv_from AND @lv_to.

    SELECT tcode AS name, COUNT(*) AS cnt
      FROM cdhdr
      INTO TABLE @lt_tcodes
      WHERE udate BETWEEN @lv_from AND @lv_to
        AND tcode <> ''
      GROUP BY tcode.

*   Development object adjustments: version directory entries per day.
    SELECT datum AS stat_date, COUNT(*) AS cnt
      FROM vrsd
      INTO TABLE @lt_dev_objects
      WHERE datum BETWEEN @lv_from AND @lv_to
      GROUP BY datum.

    SELECT objtype AS name, COUNT(*) AS cnt
      FROM vrsd
      INTO TABLE @lt_obj_types
      WHERE datum BETWEEN @lv_from AND @lv_to
      GROUP BY objtype.

*   Transport requests per day.
    SELECT as4date AS stat_date, COUNT(*) AS cnt
      FROM e070
      INTO TABLE @lt_transports
      WHERE as4date BETWEEN @lv_from AND @lv_to
      GROUP BY as4date.

*   Currently logged-on users.
    SELECT COUNT(*)
      FROM usr41
      INTO @lv_online.

*   Totals for the KPI cards.
    LOOP AT lt_user_ops ASSIGNING FIELD-SYMBOL(<ls_user_op>).
      rs_stats-user_ops = rs_stats-user_ops + <ls_user_op>-cnt.
    ENDLOOP.
    LOOP AT lt_dev_objects ASSIGNING FIELD-SYMBOL(<ls_dev_object>).
      rs_stats-dev_objects = rs_stats-dev_objects + <ls_dev_object>-cnt.
    ENDLOOP.
    LOOP AT lt_transports ASSIGNING FIELD-SYMBOL(<ls_transport>).
      rs_stats-transports = rs_stats-transports + <ls_transport>-cnt.
    ENDLOOP.
    rs_stats-active_users = lines( lt_users ).
    rs_stats-online_users = lv_online.

*   One series row per day keeps the chart axis continuous.
    lv_day = lv_from.
    WHILE lv_day <= lv_to.
      APPEND VALUE #( date = lv_day ) TO rs_stats-series.
      lv_day = lv_day + 1.
    ENDWHILE.

    LOOP AT lt_user_ops ASSIGNING <ls_user_op>.
      READ TABLE rs_stats-series ASSIGNING FIELD-SYMBOL(<ls_series>)
        WITH KEY date = <ls_user_op>-stat_date.
      IF sy-subrc = 0.
        <ls_series>-user_ops = <ls_user_op>-cnt.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_dev_objects ASSIGNING <ls_dev_object>.
      READ TABLE rs_stats-series ASSIGNING <ls_series>
        WITH KEY date = <ls_dev_object>-stat_date.
      IF sy-subrc = 0.
        <ls_series>-dev_objects = <ls_dev_object>-cnt.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_transports ASSIGNING <ls_transport>.
      READ TABLE rs_stats-series ASSIGNING <ls_series>
        WITH KEY date = <ls_transport>-stat_date.
      IF sy-subrc = 0.
        <ls_series>-transports = <ls_transport>-cnt.
      ENDIF.
    ENDLOOP.

*   Top lists: sort and truncate in ABAP because ABAP SQL cannot order by
*   an aggregate expression.
    SORT lt_tcodes BY cnt DESCENDING name ASCENDING.
    rs_stats-top_tcodes = get_top( lt_tcodes ).
    SORT lt_obj_types BY cnt DESCENDING name ASCENDING.
    rs_stats-top_obj_types = get_top( lt_obj_types ).
  ENDMETHOD.

  METHOD to_json.
    " Serialize the statistics payload as JSON.
    DATA lv_json TYPE string.

    lv_json = `{"status":"ok","days":` && |{ is_stats-days }|.
    lv_json = lv_json && `,"fromDate":"` && |{ is_stats-from_date DATE = ISO }| && `"`.
    lv_json = lv_json && `,"toDate":"` && |{ is_stats-to_date DATE = ISO }| && `"`.
    lv_json = lv_json && `,"generatedAt":"` && is_stats-generated_at && `"`.
    lv_json = lv_json && `,"kpi":{"userOps":` && |{ is_stats-user_ops }|.
    lv_json = lv_json && `,"activeUsers":` && |{ is_stats-active_users }|.
    lv_json = lv_json && `,"devObjects":` && |{ is_stats-dev_objects }|.
    lv_json = lv_json && `,"transports":` && |{ is_stats-transports }|.
    lv_json = lv_json && `,"onlineUsers":` && |{ is_stats-online_users }| && `}`.

    lv_json = lv_json && `,"series":[`.
    LOOP AT is_stats-series ASSIGNING FIELD-SYMBOL(<ls_series>).
      IF sy-tabix > 1.
        lv_json = lv_json && `,`.
      ENDIF.
      lv_json = lv_json && `{"date":"` && |{ <ls_series>-date DATE = ISO }| &&
                 `","userOps":` && |{ <ls_series>-user_ops }| &&
                 `,"devObjects":` && |{ <ls_series>-dev_objects }| &&
                 `,"transports":` && |{ <ls_series>-transports }| && `}`.
    ENDLOOP.
    lv_json = lv_json && `]`.

    lv_json = lv_json && `,"topTcodes":[` &&
               to_json_name_list( is_stats-top_tcodes ) && `]`.
    lv_json = lv_json && `,"topObjectTypes":[` &&
               to_json_name_list( is_stats-top_obj_types ) && `]`.
    lv_json = lv_json && `}`.

    rv_json = lv_json.
  ENDMETHOD.

  METHOD to_json_name_list.
    " Serialize a top list as a JSON array.
    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      IF sy-tabix > 1.
        rv_json = rv_json && `,`.
      ENDIF.
      rv_json = rv_json && `{"name":"` && escape_json( <ls_item>-name ) &&
                 `","count":` && |{ <ls_item>-cnt }| && `}`.
    ENDLOOP.
  ENDMETHOD.

  METHOD escape_json.
    " Escape a JSON string value.
    DATA lv_text TYPE string.

    lv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN lv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_text WITH '\"'.
    rv_text = lv_text.
  ENDMETHOD.

  METHOD serve_mime.
    " Read a MIME asset and serve it as the HTTP response.
    DATA: lv_content TYPE xstring,
          lv_mime    TYPE string.

    lv_content = read_mime( iv_file ).
    IF lv_content IS INITIAL.
      respond_json( io_server = io_server
                    iv_status = 404
                    iv_json   = `{"status":"error","message":"asset not found"}` ).
      RETURN.
    ENDIF.

    lv_mime = COND string(
      WHEN iv_file = gc_mime-js  THEN 'application/javascript'
      WHEN iv_file = gc_mime-css THEN 'text/css'
      ELSE 'text/html' ).

    io_server->response->set_status( code = 200 reason = 'OK' ).
    io_server->response->set_header_field( name  = 'Content-Type'
                                            value = |{ lv_mime }; charset=utf-8| ).
    io_server->response->set_header_field( name  = 'Cache-Control'
                                            value = 'no-store' ).
    io_server->response->set_data( data = lv_content ).
  ENDMETHOD.

  METHOD respond_json.
    " Send a JSON response with no-store caching.
    DATA lv_reason TYPE string.

    lv_reason = COND string(
      WHEN iv_status = 200 THEN 'OK'
      WHEN iv_status = 404 THEN 'Not Found'
      WHEN iv_status = 405 THEN 'Method Not Allowed'
      ELSE 'Error' ).

    io_server->response->set_status( code = iv_status reason = lv_reason ).
    io_server->response->set_header_field( name  = 'Content-Type'
                                            value = 'application/json; charset=utf-8' ).
    io_server->response->set_header_field( name  = 'Cache-Control'
                                            value = 'no-store' ).
    io_server->response->set_cdata( data = iv_json ).
  ENDMETHOD.

  METHOD get_days.
    " Parse and clamp the days query parameter.
    DATA: lv_days  TYPE i,
          lv_pair  TYPE string,
          lv_raw   TYPE string,
          lt_pairs TYPE string_table.

    lv_days = gc_default_days.
    SPLIT iv_query AT '&' INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO lv_pair.
      IF lv_pair CP 'days=*'.
        lv_raw = substring_after( val = lv_pair sub = 'days=' ).
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_raw IS NOT INITIAL.
      TRY.
          lv_days = CONV i( lv_raw ).
        CATCH cx_sy_conversion_no_number.
      ENDTRY.
    ENDIF.

    lv_days = nmax( val1 = gc_min_days
                    val2 = nmin( val1 = gc_max_days val2 = lv_days ) ).
    rv_days = lv_days.
  ENDMETHOD.

  METHOD read_mime.
    " Read a MIME repository resource, empty on failure.
    DATA: lv_content TYPE xstring,
          lv_mime    TYPE string.
    DATA(lr_api) = cl_mime_repository_api=>if_mr_api~get_api( ).

    CALL METHOD lr_api->get
      EXPORTING
        i_url       = |{ gc_mime-root }/{ iv_file }|
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

    rv_content = lv_content.
  ENDMETHOD.

  METHOD get_top.
    " Truncate a sorted count list to the configured top size.
    DATA lv_count TYPE i.

    LOOP AT it_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      lv_count = lv_count + 1.
      IF lv_count > gc_top_count.
        EXIT.
      ENDIF.
      APPEND VALUE #( name = <ls_row>-name
                      cnt  = <ls_row>-cnt ) TO rt_top.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
