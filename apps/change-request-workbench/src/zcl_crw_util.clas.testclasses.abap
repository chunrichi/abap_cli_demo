CLASS ltcl_crw_util DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS number_id_is_10_digits FOR TESTING.
    METHODS format_id FOR TESTING.
    METHODS now_is_14_digits FOR TESTING.
    METHODS uuid_is_32 FOR TESTING.
ENDCLASS.

CLASS ltcl_crw_util IMPLEMENTATION.
  METHOD number_id_is_10_digits.
    DATA(lv_id) = zcl_crw_util=>number_id( 42 ).

    cl_abap_unit_assert=>assert_equals( act = lv_id exp = '0000000042' ).
  ENDMETHOD.

  METHOD format_id.
    DATA(lv_id) = zcl_crw_util=>format_id( iv_prefix = 'CR' iv_number = 42 ).

    cl_abap_unit_assert=>assert_equals( act = lv_id exp = 'CR-0000000042' ).
  ENDMETHOD.

  METHOD now_is_14_digits.
    DATA(lv_timestamp) = zcl_crw_util=>now( ).

    cl_abap_unit_assert=>assert_equals( act = strlen( lv_timestamp ) exp = 14 ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_timestamp CO '0123456789' ) ).
  ENDMETHOD.

  METHOD uuid_is_32.
    DATA(lv_uuid) = zcl_crw_util=>uuid( ).

    cl_abap_unit_assert=>assert_equals( act = strlen( lv_uuid ) exp = 32 ).
  ENDMETHOD.
ENDCLASS.
