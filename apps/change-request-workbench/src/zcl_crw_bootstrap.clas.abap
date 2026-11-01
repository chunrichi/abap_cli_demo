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
               gc_version       TYPE zcrw_version-version_no VALUE '1.0.0',
               gc_notes         TYPE zcrw_version-notes VALUE 'M1 schema bootstrap',
               gc_profile       TYPE zcrw_appr_cfg-profile_id VALUE 'STD_DEFAULT',
               gc_step          TYPE zcrw_appr_cfg-step_no VALUE '01',
               gc_approver_role TYPE zcrw_appr_cfg-approver_role VALUE 'CRW_APPROVER',
               gc_object_type   TYPE zcrw_appr_cfg-object_type VALUE 'REQ',
               gc_req_type      TYPE zcrw_appr_cfg-req_type VALUE 'STD',
               gc_mandatory     TYPE zcrw_appr_cfg-mandatory VALUE 'X',
               gc_role          TYPE zcrw_role-role VALUE 'ADMIN',
               gc_scope         TYPE zcrw_role-scope_type VALUE 'GLOBAL',
               gc_valid_to      TYPE zcrw_role-valid_to VALUE '99991231'.

    CLASS-METHODS seed_config
      RETURNING VALUE(rv_inserted) TYPE i.
ENDCLASS.

CLASS zcl_crw_bootstrap IMPLEMENTATION.
  METHOD run.
    rs_result-intervals_created = zcl_crw_number=>ensure_intervals( ).
    rs_result-config_inserted = seed_config( ).

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD seed_config.
    DATA ls_version TYPE zcrw_version.
    DATA ls_appr    TYPE zcrw_appr_cfg.
    DATA ls_role    TYPE zcrw_role.

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

    " Default approval matrix row.
    ls_appr-profile_id    = gc_profile.
    ls_appr-step_no       = gc_step.
    ls_appr-approver_role = gc_approver_role.
    ls_appr-object_type   = gc_object_type.
    ls_appr-req_type      = gc_req_type.
    ls_appr-mandatory     = gc_mandatory.
    INSERT zcrw_appr_cfg FROM ls_appr.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.

    " Current user becomes the initial administrator.
    ls_role-user_id    = sy-uname.
    ls_role-role       = gc_role.
    ls_role-scope_type = gc_scope.
    ls_role-valid_from = sy-datum.
    ls_role-valid_to   = gc_valid_to.
    INSERT zcrw_role FROM ls_role.
    IF sy-subrc = 0.
      rv_inserted = rv_inserted + 1.
    ENDIF.
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
