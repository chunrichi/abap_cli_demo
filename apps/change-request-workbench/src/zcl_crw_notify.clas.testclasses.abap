CLASS ltcl_crw_notify DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS type_is_valid_for_pending FOR TESTING.
    METHODS type_is_valid_for_unknown FOR TESTING.
    METHODS create_requires_user FOR TESTING.
    METHODS create_requires_title FOR TESTING.
    METHODS mark_read_requires_id FOR TESTING.
ENDCLASS.

CLASS ltcl_crw_notify IMPLEMENTATION.
  METHOD type_is_valid_for_pending.
    cl_abap_unit_assert=>assert_true(
      act = zcl_crw_notify=>type_is_valid( zcl_crw_notify=>gc_type_approval_pending ) ).
  ENDMETHOD.

  METHOD type_is_valid_for_unknown.
    cl_abap_unit_assert=>assert_false(
      act = zcl_crw_notify=>type_is_valid( 'NOT_A_TYPE' ) ).
  ENDMETHOD.

  METHOD create_requires_user.
    TRY.
        DATA(ls_result) = zcl_crw_notify=>emit( iv_user  = ''
                                                iv_type  = zcl_crw_notify=>gc_type_info
                                                iv_title = 'Unit test' ).
        cl_abap_unit_assert=>fail( 'A notification without a user must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.

  METHOD create_requires_title.
    TRY.
        DATA(ls_result) = zcl_crw_notify=>emit( iv_user  = 'UNIT_TEST'
                                                iv_type  = zcl_crw_notify=>gc_type_info
                                                iv_title = '' ).
        cl_abap_unit_assert=>fail( 'A notification without a title must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.

  METHOD mark_read_requires_id.
    TRY.
        DATA(lv_updated) = zcl_crw_notify=>mark_read( iv_user = 'UNIT_TEST' iv_notify_id = '' ).
        cl_abap_unit_assert=>fail( 'Marking read without an id must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
