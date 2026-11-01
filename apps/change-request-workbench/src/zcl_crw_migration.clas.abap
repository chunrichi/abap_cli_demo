CLASS zcl_crw_migration DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CLASS-METHODS run
      RETURNING VALUE(rv_version) TYPE zcrw_version-version_no
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CLASS-METHODS current_version
      RETURNING VALUE(rv_version) TYPE zcrw_version-version_no.
ENDCLASS.

CLASS zcl_crw_migration IMPLEMENTATION.
  METHOD run.
    DATA lv_component TYPE zcrw_version-component.

    lv_component = 'CRW'.

*   Bootstrap is idempotent and owns the current schema/config seeds.
    zcl_crw_bootstrap=>run( ).

    rv_version = current_version( ).
    IF rv_version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'MIGRATION_VERSION'
                  iv_text = 'No component version row after the migration run'.
    ENDIF.
  ENDMETHOD.

  METHOD current_version.
    DATA lv_component TYPE zcrw_version-component.

    lv_component = 'CRW'.
    SELECT MAX( version_no )
      FROM zcrw_version
      WHERE component = @lv_component
      INTO @rv_version.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    DATA lv_from TYPE zcrw_version-version_no.

    TRY.
        lv_from = current_version( ).
        DATA(lv_to) = run( ).
        out->write( |CRW_MIGRATION_OK from={ lv_from } to={ lv_to }| ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        out->write( |CRW_MIGRATION_FAIL { lx_error->mv_code } { lx_error->mv_text }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
