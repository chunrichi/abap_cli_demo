CLASS zcl_crw_json DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CLASS-METHODS serialize
      IMPORTING iv_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS deserialize
      IMPORTING iv_json TYPE string
      CHANGING  cs_data TYPE any.

    CLASS-METHODS paged
      IMPORTING it_items        TYPE STANDARD TABLE
                iv_page         TYPE i
                iv_page_size    TYPE i
                iv_total        TYPE i
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS has_key
      IMPORTING iv_json          TYPE string
                iv_key           TYPE string
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    CLASS-METHODS format_timestamp
      IMPORTING iv_timestamp TYPE char14
      RETURNING VALUE(rv_iso) TYPE string.

    CLASS-METHODS parse_timestamp
      IMPORTING iv_iso             TYPE string
      RETURNING VALUE(rv_timestamp) TYPE char14.

    CLASS-METHODS format_date
      IMPORTING iv_date        TYPE dats
      RETURNING VALUE(rv_iso) TYPE string.

    CLASS-METHODS parse_date
      IMPORTING iv_iso         TYPE string
      RETURNING VALUE(rv_date) TYPE dats.

    CLASS-METHODS escape
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS only_digits
      IMPORTING iv_text          TYPE string
                iv_length        TYPE i
      RETURNING VALUE(rv_digits) TYPE string.
ENDCLASS.

CLASS zcl_crw_json IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    TYPES: BEGIN OF ty_probe,
             id           TYPE string,
             display_id   TYPE string,
             request_type TYPE string,
             admin        TYPE abap_bool,
             items        TYPE string_table,
           END OF ty_probe.

    DATA ls_probe TYPE ty_probe.
    DATA lv_json TYPE string.

    ls_probe-id = '0000000123'.
    ls_probe-display_id = 'CR-0000000123'.
    ls_probe-request_type = 'STD'.
    ls_probe-admin = abap_true.
    APPEND 'A' TO ls_probe-items.
    APPEND 'B' TO ls_probe-items.

    lv_json = serialize( ls_probe ).
    out->write( |CRW_JSON_OK { lv_json }| ).
    out->write( |CRW_JSON_DATE { format_date( '20261101' ) } { format_date( '00000000' ) } { parse_date( '2026-11-01' ) }| ).
    out->write( |CRW_JSON_TS { format_timestamp( '20261101220000' ) } { parse_timestamp( '2026-11-01T22:00:00' ) }| ).
  ENDMETHOD.

  METHOD serialize.
    TRY.
        rv_json = /ui2/cl_json=>serialize( data        = iv_data
                                           pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                           compress    = abap_true ).
      CATCH cx_root.
        rv_json = '{}'.
    ENDTRY.
  ENDMETHOD.

  METHOD deserialize.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                             pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                   CHANGING  data        = cs_data ).
      CATCH cx_root.
        CLEAR cs_data.
    ENDTRY.
  ENDMETHOD.

  METHOD paged.
    rv_json = |\{"items":{ serialize( it_items ) },"page":{ iv_page }| &&
              |,"pageSize":{ iv_page_size },"total":{ iv_total }\}|.
  ENDMETHOD.

  METHOD has_key.
    DATA lv_pattern TYPE string.

    lv_pattern = '"' && iv_key && '"[ ]*:'.
    FIND REGEX lv_pattern IN iv_json.
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD format_timestamp.
    DATA lv_timestamp TYPE char14.

    IF iv_timestamp IS INITIAL.
      rv_iso = ''.
      RETURN.
    ENDIF.

    lv_timestamp = iv_timestamp.
    IF lv_timestamp(4) = '0000' OR lv_timestamp+4(2) = '00' OR lv_timestamp+6(2) = '00'.
      rv_iso = ''.
      RETURN.
    ENDIF.

    rv_iso = |{ lv_timestamp(4) }-{ lv_timestamp+4(2) }-{ lv_timestamp+6(2) }| &&
             |T{ lv_timestamp+8(2) }:{ lv_timestamp+10(2) }:{ lv_timestamp+12(2) }|.
  ENDMETHOD.

  METHOD parse_timestamp.
    DATA lv_digits TYPE string.

    lv_digits = only_digits( iv_text = iv_iso iv_length = 14 ).
    IF lv_digits IS INITIAL OR lv_digits(4) = '0000'.
      rv_timestamp = ''.
    ELSE.
      rv_timestamp = lv_digits.
    ENDIF.
  ENDMETHOD.

  METHOD format_date.
    DATA lv_date TYPE dats.
    DATA lv_text TYPE string.

    lv_date = iv_date.
    lv_text = CONV string( lv_date ).
    IF strlen( lv_text ) <> 8 OR lv_text(4) = '0000' OR lv_text+4(2) = '00' OR lv_text+6(2) = '00'.
      rv_iso = ''.
      RETURN.
    ENDIF.

    rv_iso = |{ lv_text(4) }-{ lv_text+4(2) }-{ lv_text+6(2) }|.
  ENDMETHOD.

  METHOD parse_date.
    DATA lv_digits TYPE string.

    lv_digits = only_digits( iv_text = iv_iso iv_length = 8 ).
    IF lv_digits IS INITIAL OR lv_digits(4) = '0000'.
      CLEAR rv_date.
    ELSE.
      rv_date = lv_digits.
    ENDIF.
  ENDMETHOD.

  METHOD only_digits.
    DATA: lv_length TYPE i,
          lv_index  TYPE i,
          lv_char   TYPE c LENGTH 1.

    lv_length = strlen( iv_text ).
    WHILE lv_index < lv_length AND strlen( rv_digits ) < iv_length.
      lv_char = substring( val = iv_text off = lv_index len = 1 ).
      IF lv_char CO '0123456789'.
        rv_digits = rv_digits && lv_char.
      ENDIF.
      lv_index = lv_index + 1.
    ENDWHILE.

    IF strlen( rv_digits ) < iv_length.
      CLEAR rv_digits.
    ENDIF.
  ENDMETHOD.

  METHOD escape.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_text WITH '\t'.
  ENDMETHOD.
ENDCLASS.
