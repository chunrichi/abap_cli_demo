CLASS ltcl_crw_json DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    TYPES: BEGIN OF ts_probe,
             id         TYPE string,
             display_id TYPE string,
             active     TYPE abap_bool,
             items      TYPE string_table,
           END OF ts_probe.

    METHODS serialize_camel_case FOR TESTING.
    METHODS deserialize_camel_case FOR TESTING.
    METHODS has_key_detection FOR TESTING.
    METHODS timestamp_roundtrip FOR TESTING.
    METHODS date_roundtrip FOR TESTING.
    METHODS initial_dates FOR TESTING.
    METHODS escape_text FOR TESTING.
    METHODS paged_envelope FOR TESTING.
ENDCLASS.

CLASS ltcl_crw_json IMPLEMENTATION.
  METHOD serialize_camel_case.
    DATA ls_probe TYPE ts_probe.

    ls_probe-id = '0000000001'.
    ls_probe-display_id = 'CR-0000000001'.
    ls_probe-active = abap_true.
    APPEND 'A' TO ls_probe-items.

    DATA(lv_json) = zcl_crw_json=>serialize( ls_probe ).

    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"displayId"' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"active":true' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"items":["A"]' ) ).
  ENDMETHOD.

  METHOD deserialize_camel_case.
    DATA lv_json TYPE string.
    DATA ls_probe TYPE ts_probe.

    lv_json = '{"id":"42","displayId":"CR-42","active":true,"items":["X","Y"]}'.
    zcl_crw_json=>deserialize( EXPORTING iv_json = lv_json CHANGING cs_data = ls_probe ).

    cl_abap_unit_assert=>assert_equals( act = ls_probe-display_id exp = 'CR-42' ).
    cl_abap_unit_assert=>assert_true( act = ls_probe-active ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_probe-items ) exp = 2 ).
  ENDMETHOD.

  METHOD has_key_detection.
    DATA lv_json TYPE string.

    lv_json = '{"title":"A","priority":"3"}'.

    cl_abap_unit_assert=>assert_true( act = zcl_crw_json=>has_key( iv_json = lv_json iv_key = 'title' ) ).
    cl_abap_unit_assert=>assert_true( act = zcl_crw_json=>has_key( iv_json = lv_json iv_key = 'priority' ) ).
    cl_abap_unit_assert=>assert_false( act = zcl_crw_json=>has_key( iv_json = lv_json iv_key = 'owner' ) ).
  ENDMETHOD.

  METHOD timestamp_roundtrip.
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>format_timestamp( '20261101220000' )
                                        exp = '2026-11-01T22:00:00' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>parse_timestamp( '2026-11-01T22:00:00' )
                                        exp = '20261101220000' ).
  ENDMETHOD.

  METHOD date_roundtrip.
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>format_date( '20261101' ) exp = '2026-11-01' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>parse_date( '2026-11-01' ) exp = '20261101' ).
  ENDMETHOD.

  METHOD initial_dates.
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>format_date( '00000000' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_crw_json=>format_timestamp( '' ) exp = '' ).
    cl_abap_unit_assert=>assert_initial( act = zcl_crw_json=>parse_date( '' ) ).
  ENDMETHOD.

  METHOD escape_text.
    DATA(lv_text) = zcl_crw_json=>escape( 'a"b\c' ).

    cl_abap_unit_assert=>assert_equals( act = lv_text exp = 'a\"b\\c' ).
  ENDMETHOD.

  METHOD paged_envelope.
    DATA lt_items TYPE string_table.

    APPEND 'A' TO lt_items.
    DATA(lv_json) = zcl_crw_json=>paged( it_items = lt_items
                                        iv_page = 2
                                        iv_page_size = 50
                                        iv_total = 51 ).

    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"items":["A"]' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"page":2' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_json CS '"total":51' ) ).
  ENDMETHOD.
ENDCLASS.
