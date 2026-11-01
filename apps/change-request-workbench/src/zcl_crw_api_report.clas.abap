CLASS zcl_crw_api_report DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_api_report IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_kind TYPE string.

    IF lines( it_segments ) < 2.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown report path'.
    ENDIF.

    IF io_ctx->mv_method <> 'GET'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Reports are read-only'.
    ENDIF.

    lv_kind = it_segments[ 2 ].

    CASE lv_kind.
      WHEN 'changes'.
        io_ctx->set_data( zcl_crw_report_svc=>changes( ) ).
      WHEN 'duration'.
        io_ctx->set_data( zcl_crw_report_svc=>duration( ) ).
      WHEN 'overdue'.
        io_ctx->set_data( zcl_crw_report_svc=>overdue( ) ).
      WHEN 'to-c'.
        io_ctx->set_data( zcl_crw_report_svc=>to_c( ) ).
      WHEN 'export.csv'.
        DATA(lv_csv) = zcl_crw_report_svc=>csv( io_ctx->param( 'type' ) ).
        io_ctx->set_text( iv_text         = lv_csv
                          iv_content_type = 'text/csv; charset=utf-8'
                          iv_filename     = |crw-{ COND string( WHEN io_ctx->param( 'type' ) IS INITIAL THEN 'changes' ELSE io_ctx->param( 'type' ) ) }-export.csv| ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown report { lv_kind }|.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.
