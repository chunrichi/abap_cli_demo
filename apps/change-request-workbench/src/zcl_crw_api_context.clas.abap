CLASS zcl_crw_api_context DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_param,
             name  TYPE string,
             value TYPE string,
           END OF ty_param.
    TYPES tt_params TYPE STANDARD TABLE OF ty_param WITH EMPTY KEY.

    DATA mv_method         TYPE string.
    DATA mv_path           TYPE string.
    DATA mv_query          TYPE string.
    DATA mv_body           TYPE string.
    DATA mv_user           TYPE string.
    DATA mv_correlation_id TYPE string.
    DATA mv_is_admin       TYPE abap_bool.
    DATA mt_roles          TYPE zcl_crw_auth=>tt_roles.
    DATA mt_params         TYPE tt_params.

*   Response carrier filled by controllers.
    DATA mv_status       TYPE i.
    DATA mv_content_type TYPE string.
    DATA mv_response     TYPE string.
    DATA mv_raw          TYPE xstring.
    DATA mv_is_raw       TYPE abap_bool.
    DATA mv_is_text      TYPE abap_bool.
    DATA mv_content_disposition TYPE string.

    METHODS add_param
      IMPORTING iv_name  TYPE string
                iv_value TYPE string.

    METHODS param
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS param_exists
      IMPORTING iv_name          TYPE string
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    METHODS param_int
      IMPORTING iv_name       TYPE string
                iv_default    TYPE i DEFAULT 0
      RETURNING VALUE(rv_value) TYPE i.

    METHODS set_data
      IMPORTING iv_data TYPE any.

    METHODS set_paged
      IMPORTING it_items     TYPE STANDARD TABLE
                iv_page      TYPE i
                iv_page_size TYPE i
                iv_total     TYPE i.

    METHODS set_json
      IMPORTING iv_data_json TYPE string.

    METHODS set_text
      IMPORTING iv_text         TYPE string
                iv_content_type TYPE string
                iv_filename     TYPE string DEFAULT ''.

    METHODS set_raw
      IMPORTING iv_data         TYPE xstring
                iv_content_type TYPE string.

    METHODS set_status
      IMPORTING iv_status TYPE i.

    METHODS json_envelope
      IMPORTING iv_data_json    TYPE string
      RETURNING VALUE(rv_json)  TYPE string.

    METHODS error_envelope
      IMPORTING iv_code        TYPE string
                iv_message     TYPE string
                iv_details     TYPE string DEFAULT '{}'
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.

CLASS zcl_crw_api_context IMPLEMENTATION.
  METHOD add_param.
    DATA lv_name TYPE string.

    lv_name = iv_name.
    TRANSLATE lv_name TO UPPER CASE.
    APPEND VALUE #( name = lv_name value = iv_value ) TO mt_params.
  ENDMETHOD.

  METHOD param.
    DATA lv_name TYPE string.

    lv_name = iv_name.
    TRANSLATE lv_name TO UPPER CASE.
    READ TABLE mt_params INTO DATA(ls_param) WITH KEY name = lv_name.
    IF sy-subrc = 0.
      rv_value = ls_param-value.
    ENDIF.
  ENDMETHOD.

  METHOD param_exists.
    DATA lv_name TYPE string.

    lv_name = iv_name.
    TRANSLATE lv_name TO UPPER CASE.
    READ TABLE mt_params TRANSPORTING NO FIELDS WITH KEY name = lv_name.
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD param_int.
    DATA lv_value TYPE string.

    lv_value = param( iv_name ).
    IF lv_value IS INITIAL.
      rv_value = iv_default.
      RETURN.
    ENDIF.

    TRY.
        rv_value = CONV i( lv_value ).
      CATCH cx_sy_conversion_no_number.
        rv_value = iv_default.
    ENDTRY.
  ENDMETHOD.

  METHOD set_data.
    mv_response = json_envelope( zcl_crw_json=>serialize( iv_data ) ).
    mv_content_type = 'application/json; charset=utf-8'.
    mv_is_raw = abap_false.
    mv_status = COND #( WHEN mv_status IS INITIAL THEN 200 ELSE mv_status ).
  ENDMETHOD.

  METHOD set_paged.
    mv_response = json_envelope( zcl_crw_json=>paged( it_items     = it_items
                                                       iv_page      = iv_page
                                                       iv_page_size = iv_page_size
                                                       iv_total     = iv_total ) ).
    mv_content_type = 'application/json; charset=utf-8'.
    mv_is_raw = abap_false.
    mv_status = COND #( WHEN mv_status IS INITIAL THEN 200 ELSE mv_status ).
  ENDMETHOD.

  METHOD set_json.
    mv_response = json_envelope( iv_data_json ).
    mv_content_type = 'application/json; charset=utf-8'.
    mv_is_raw = abap_false.
    mv_status = COND #( WHEN mv_status IS INITIAL THEN 200 ELSE mv_status ).
  ENDMETHOD.

  METHOD set_text.
    mv_response   = iv_text.
    mv_content_type = iv_content_type.
    mv_is_text    = abap_true.
    mv_is_raw     = abap_false.
    mv_status     = COND #( WHEN mv_status IS INITIAL THEN 200 ELSE mv_status ).
    IF iv_filename IS NOT INITIAL.
      mv_content_disposition = |attachment; filename="{ iv_filename }"|.
    ENDIF.
  ENDMETHOD.

  METHOD set_raw.
    mv_raw = iv_data.
    mv_content_type = iv_content_type.
    mv_is_raw = abap_true.
    mv_status = COND #( WHEN mv_status IS INITIAL THEN 200 ELSE mv_status ).
  ENDMETHOD.

  METHOD set_status.
    mv_status = iv_status.
  ENDMETHOD.

  METHOD json_envelope.
    rv_json = |\{"status":"success","data":{ iv_data_json }\}|.
  ENDMETHOD.

  METHOD error_envelope.
    rv_json = |\{"status":"error","code":"{ zcl_crw_json=>escape( iv_code ) }"| &&
              |,"message":"{ zcl_crw_json=>escape( iv_message ) }"| &&
              |,"details":{ iv_details }| &&
              |,"correlationId":"{ mv_correlation_id }"\}|.
  ENDMETHOD.
ENDCLASS.
