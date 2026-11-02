CLASS ltcl_crw_appr_svc DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS reassign_requires_id FOR TESTING.
    METHODS reassign_requires_approver FOR TESTING.
    METHODS reassign_rejects_long_approver FOR TESTING.
ENDCLASS.

CLASS ltcl_crw_appr_svc IMPLEMENTATION.
  METHOD reassign_requires_id.
    TRY.
        zcl_crw_appr_svc=>reassign( iv_appr_id      = ''
                                    iv_user         = 'UNIT_TEST'
                                    iv_new_approver = 'UNIT_TEST2' ).
        cl_abap_unit_assert=>fail( 'A reassign without an approval id must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.

  METHOD reassign_requires_approver.
    TRY.
        zcl_crw_appr_svc=>reassign( iv_appr_id      = 'PROBE'
                                    iv_user         = 'UNIT_TEST'
                                    iv_new_approver = '' ).
        cl_abap_unit_assert=>fail( 'A reassign without a new approver must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.

  METHOD reassign_rejects_long_approver.
    TRY.
        zcl_crw_appr_svc=>reassign( iv_appr_id      = 'PROBE'
                                    iv_user         = 'UNIT_TEST'
                                    iv_new_approver = 'A_USER_ID_LONGER_THAN_12' ).
        cl_abap_unit_assert=>fail( 'An approver id longer than 12 characters must be rejected' ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'VALIDATION_ERROR' ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
