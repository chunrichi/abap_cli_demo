CLASS zcl_crw_test_data DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CLASS-METHODS reset_business_data
      RETURNING VALUE(rv_deleted) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS seed_approver_roles
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_test_data IMPLEMENTATION.
  METHOD reset_business_data.
    DELETE FROM zcrw_task.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_cd.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_req.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_tr.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_sched.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_appr.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_hist.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_note.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_notify.
    rv_deleted = rv_deleted + sy-dbcnt.
    DELETE FROM zcrw_log.
    rv_deleted = rv_deleted + sy-dbcnt.
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD seed_approver_roles.
    DATA ls_role TYPE zcrw_role.

    ls_role-user_id = sy-uname.
    ls_role-role = zcl_crw_auth=>gc_change_manager.
    ls_role-scope_type = 'GLOBAL'.
    ls_role-scope_id = ''.
    ls_role-valid_from = sy-datum.
    ls_role-valid_to = '99991231'.
    INSERT zcrw_role FROM ls_role.
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
    ENDIF.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    TRY.
        DATA(lv_deleted) = reset_business_data( ).
        seed_approver_roles( ).
        out->write( |CRW_TEST_DATA_RESET rows={ lv_deleted }| ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        out->write( |CRW_TEST_DATA_FAIL { lx_error->mv_code } { lx_error->mv_text }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
