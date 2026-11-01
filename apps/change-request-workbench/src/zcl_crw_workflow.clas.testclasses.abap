CLASS ltcl_crw_workflow DEFINITION FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS cr_happy_path FOR TESTING.
    METHODS cr_rejection_and_revise FOR TESTING.
    METHODS cr_cancel_rules FOR TESTING.
    METHODS cd_happy_path FOR TESTING.
    METHODS cd_schedule_and_confirm FOR TESTING.
    METHODS cd_closing_rules FOR TESTING.
    METHODS task_transitions FOR TESTING.
    METHODS terminal_states FOR TESTING.
    METHODS allowed_actions_req FOR TESTING.
    METHODS allowed_actions_cd FOR TESTING.

    METHODS assert_target
      IMPORTING iv_type   TYPE string
                iv_from   TYPE string
                iv_action TYPE string
                iv_exp    TYPE string.

    METHODS assert_invalid
      IMPORTING iv_type   TYPE string
                iv_from   TYPE string
                iv_action TYPE string.
ENDCLASS.

CLASS ltcl_crw_workflow IMPLEMENTATION.
  METHOD cr_happy_path.
    assert_target( iv_type = 'REQ' iv_from = 'NEW' iv_action = 'SUBMIT' iv_exp = 'PENDING_APPROVAL' ).
    assert_target( iv_type = 'REQ' iv_from = 'PENDING_APPROVAL' iv_action = 'APPROVE_STEP' iv_exp = 'PENDING_APPROVAL' ).
    assert_target( iv_type = 'REQ' iv_from = 'APPROVED' iv_action = 'START_PROGRESS' iv_exp = 'IN_PROGRESS' ).
    assert_target( iv_type = 'REQ' iv_from = 'IN_PROGRESS' iv_action = 'CLOSE' iv_exp = 'CLOSED' ).
    assert_target( iv_type = 'REQ' iv_from = 'PENDING_APPROVAL' iv_action = 'WITHDRAW' iv_exp = 'NEW' ).
  ENDMETHOD.

  METHOD cr_rejection_and_revise.
    assert_target( iv_type = 'REQ' iv_from = 'PENDING_APPROVAL' iv_action = 'REJECT' iv_exp = 'REJECTED' ).
    assert_target( iv_type = 'REQ' iv_from = 'REJECTED' iv_action = 'REVISE' iv_exp = 'NEW' ).
  ENDMETHOD.

  METHOD cr_cancel_rules.
    assert_target( iv_type = 'REQ' iv_from = 'NEW' iv_action = 'CANCEL' iv_exp = 'CANCELLED' ).
    assert_target( iv_type = 'REQ' iv_from = 'APPROVED' iv_action = 'CANCEL' iv_exp = 'CANCELLED' ).
    assert_invalid( iv_type = 'REQ' iv_from = 'CLOSED' iv_action = 'CANCEL' ).
    assert_invalid( iv_type = 'REQ' iv_from = 'NEW' iv_action = 'APPROVE_STEP' ).
    assert_invalid( iv_type = 'REQ' iv_from = 'NEW' iv_action = 'MARK_READY' ).
    assert_invalid( iv_type = 'REQ' iv_from = 'APPROVED' iv_action = 'SUBMIT' ).
  ENDMETHOD.

  METHOD cd_happy_path.
    assert_target( iv_type = 'CD' iv_from = 'NEW' iv_action = 'START_DEV' iv_exp = 'IN_DEV' ).
    assert_target( iv_type = 'CD' iv_from = 'IN_DEV' iv_action = 'SUBMIT_TEST' iv_exp = 'IN_TEST' ).
    assert_target( iv_type = 'CD' iv_from = 'IN_TEST' iv_action = 'PASS_TEST' iv_exp = 'IN_TEST' ).
    assert_target( iv_type = 'CD' iv_from = 'IN_TEST' iv_action = 'SUBMIT_APPROVAL' iv_exp = 'IN_TEST' ).
    assert_target( iv_type = 'CD' iv_from = 'IN_TEST' iv_action = 'MARK_READY' iv_exp = 'READY_TO_IMPORT' ).
    assert_target( iv_type = 'CD' iv_from = 'IMPORTED' iv_action = 'CLOSE' iv_exp = 'CLOSED' ).
  ENDMETHOD.

  METHOD cd_schedule_and_confirm.
    assert_target( iv_type = 'CD' iv_from = 'READY_TO_IMPORT' iv_action = 'SCHEDULE_IMPORT' iv_exp = 'IMPORT_SCHEDULED' ).
    assert_target( iv_type = 'CD' iv_from = 'IMPORT_SCHEDULED' iv_action = 'SCHEDULE_IMPORT' iv_exp = 'READY_TO_IMPORT' ).
    assert_target( iv_type = 'CD' iv_from = 'READY_TO_IMPORT' iv_action = 'CONFIRM_IMPORT' iv_exp = 'IMPORTED' ).
    assert_target( iv_type = 'CD' iv_from = 'IMPORT_SCHEDULED' iv_action = 'CONFIRM_IMPORT' iv_exp = 'IMPORTED' ).
    assert_invalid( iv_type = 'CD' iv_from = 'IN_TEST' iv_action = 'CONFIRM_IMPORT' ).
    assert_invalid( iv_type = 'CD' iv_from = 'IMPORTED' iv_action = 'CONFIRM_IMPORT' ).
  ENDMETHOD.

  METHOD cd_closing_rules.
    assert_invalid( iv_type = 'CD' iv_from = 'IN_TEST' iv_action = 'CLOSE' ).
    assert_invalid( iv_type = 'CD' iv_from = 'NEW' iv_action = 'MARK_READY' ).
    assert_target( iv_type = 'CD' iv_from = 'IN_DEV' iv_action = 'CANCEL' iv_exp = 'CANCELLED' ).
    assert_invalid( iv_type = 'CD' iv_from = 'CLOSED' iv_action = 'CANCEL' ).
  ENDMETHOD.

  METHOD task_transitions.
    assert_target( iv_type = 'TASK' iv_from = 'OPEN' iv_action = 'START' iv_exp = 'IN_PROGRESS' ).
    assert_target( iv_type = 'TASK' iv_from = 'IN_PROGRESS' iv_action = 'DONE' iv_exp = 'DONE' ).
    assert_target( iv_type = 'TASK' iv_from = 'IN_PROGRESS' iv_action = 'CANCEL' iv_exp = 'CANCELLED' ).
    assert_invalid( iv_type = 'TASK' iv_from = 'OPEN' iv_action = 'DONE' ).
    assert_invalid( iv_type = 'TASK' iv_from = 'DONE' iv_action = 'START' ).
  ENDMETHOD.

  METHOD terminal_states.
    cl_abap_unit_assert=>assert_true( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'REQ' iv_status = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_true( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'REQ' iv_status = 'CANCELLED' ) ).
    cl_abap_unit_assert=>assert_false( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'REQ' iv_status = 'IN_PROGRESS' ) ).
    cl_abap_unit_assert=>assert_true( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'CD' iv_status = 'CLOSED' ) ).
    cl_abap_unit_assert=>assert_false( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'CD' iv_status = 'IMPORTED' ) ).
    cl_abap_unit_assert=>assert_true( act = zcl_crw_workflow=>is_terminal( iv_object_type = 'TASK' iv_status = 'DONE' ) ).
  ENDMETHOD.

  METHOD allowed_actions_req.
    DATA(lt_actions) = zcl_crw_workflow=>allowed_actions( iv_object_type = 'REQ' iv_status = 'NEW' ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_actions ) exp = 2 ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( line_exists( lt_actions[ table_line = 'SUBMIT' ] ) ) ).
  ENDMETHOD.

  METHOD allowed_actions_cd.
    DATA(lt_actions) = zcl_crw_workflow=>allowed_actions( iv_object_type = 'CD' iv_status = 'IN_TEST' ).

    cl_abap_unit_assert=>assert_true( act = xsdbool( line_exists( lt_actions[ table_line = 'MARK_READY' ] ) ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( line_exists( lt_actions[ table_line = 'START_DEV' ] ) ) ).
  ENDMETHOD.

  METHOD assert_target.
    DATA(lv_act) = zcl_crw_workflow=>target_status( iv_object_type = iv_type
                                                    iv_from        = iv_from
                                                    iv_action      = iv_action ).
    cl_abap_unit_assert=>assert_equals( act = lv_act exp = iv_exp
                                        msg = |{ iv_type } { iv_from } { iv_action }| ).
  ENDMETHOD.

  METHOD assert_invalid.
    DATA(lv_act) = zcl_crw_workflow=>target_status( iv_object_type = iv_type
                                                    iv_from        = iv_from
                                                    iv_action      = iv_action ).
    cl_abap_unit_assert=>assert_initial( act = lv_act
                                         msg = |{ iv_type } { iv_from } { iv_action } should be invalid| ).
  ENDMETHOD.
ENDCLASS.
