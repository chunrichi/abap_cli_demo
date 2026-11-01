CLASS zcl_crw_bootstrap DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_result,
             intervals_created TYPE i,
             config_inserted   TYPE i,
           END OF ty_result.

    INTERFACES if_oo_adt_classrun.

    CLASS-METHODS run
      RETURNING VALUE(rs_result) TYPE ty_result
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CONSTANTS: gc_component     TYPE zcrw_version-component VALUE 'CRW',
               gc_version       TYPE zcrw_version-version_no VALUE '1.2.0',
               gc_notes         TYPE zcrw_version-notes VALUE 'M5 P2 notification center',
               gc_profile_req   TYPE zcrw_appr_cfg-profile_id VALUE 'STD_DEFAULT',
               gc_profile_cd    TYPE zcrw_appr_cfg-profile_id VALUE 'CD_DEFAULT',
               gc_step          TYPE zcrw_appr_cfg-step_no VALUE '01',
               gc_approver_role TYPE zcrw_appr_cfg-approver_role VALUE 'CHANGE_MANAGER',
               gc_legacy_role   TYPE zcrw_appr_cfg-approver_role VALUE 'CRW_APPROVER',
               gc_mandatory     TYPE zcrw_appr_cfg-mandatory VALUE 'X',
               gc_object_req    TYPE zcrw_appr_cfg-object_type VALUE 'REQ',
               gc_object_cd     TYPE zcrw_appr_cfg-object_type VALUE 'CD',
               gc_req_type      TYPE zcrw_appr_cfg-req_type VALUE 'STD',
               gc_scope         TYPE zcrw_role-scope_type VALUE 'GLOBAL',
               gc_valid_to      TYPE zcrw_role-valid_to VALUE '99991231'.

    CLASS-METHODS seed_config
      RETURNING VALUE(rv_inserted) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS seed_roles
      RETURNING VALUE(rv_inserted) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS normalize_legacy_matrix
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_bootstrap IMPLEMENTATION.
  METHOD run.
    rs_result-intervals_created = zcl_crw_number=>ensure_intervals( ).
    rs_result-config_inserted = seed_config( ).
    rs_result-config_inserted = rs_result-config_inserted + seed_roles( ).

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD seed_config.
    DATA ls_version TYPE zcrw_version.
    DATA ls_appr TYPE zcrw_appr_cfg.

    " Version and migration bookkeeping.
    ls_version-component  = gc_component.
    ls_version-version_no = gc_version.
    ls_version-applied_at = zcl_crw_util=>now( ).
    ls_version-applied_by = sy-uname.
    ls_version-notes      = gc_notes.
    INSERT zcrw_version FROM ls_version.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.

    " Default approval matrix: one mandatory CR step and one optional CD step.
    ls_appr-profile_id    = gc_profile_req.
    ls_appr-step_no       = gc_step.
    ls_appr-approver_role = gc_approver_role.
    ls_appr-object_type   = gc_object_req.
    ls_appr-req_type      = gc_req_type.
    ls_appr-mandatory     = gc_mandatory.
    INSERT zcrw_appr_cfg FROM ls_appr.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.

    ls_appr-profile_id    = gc_profile_cd.
    ls_appr-step_no       = gc_step.
    ls_appr-approver_role = gc_approver_role.
    ls_appr-object_type   = gc_object_cd.
    ls_appr-req_type      = gc_req_type.
    ls_appr-mandatory     = ''.
    INSERT zcrw_appr_cfg FROM ls_appr.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.

    normalize_legacy_matrix( ).
  ENDMETHOD.

  METHOD seed_roles.
    DATA ls_role TYPE zcrw_role.

    " The bootstrap user is the initial administrator and change manager.
    ls_role-user_id    = sy-uname.
    ls_role-role       = zcl_crw_auth=>gc_admin.
    ls_role-scope_type = gc_scope.
    ls_role-valid_from = sy-datum.
    ls_role-valid_to   = gc_valid_to.
    INSERT zcrw_role FROM ls_role.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.

    ls_role-role = zcl_crw_auth=>gc_change_manager.
    INSERT zcrw_role FROM ls_role.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_legacy_matrix.
*   The v1.0.0 seed used the placeholder role CRW_APPROVER; align it with the
*   frozen role model so approval steps resolve to real users after upgrade.
    UPDATE zcrw_appr_cfg
      SET approver_role = @gc_approver_role
      WHERE profile_id    = @gc_profile_req
        AND step_no       = @gc_step
        AND approver_role = @gc_legacy_role.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    TRY.
        DATA(ls_result) = run( ).
        out->write( |CRW_BOOTSTRAP_OK intervals={ ls_result-intervals_created } config={ ls_result-config_inserted }| ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        out->write( |CRW_BOOTSTRAP_FAIL { lx_error->mv_code } { lx_error->mv_text }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
