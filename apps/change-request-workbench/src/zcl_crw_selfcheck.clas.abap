CLASS zcl_crw_selfcheck DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CLASS-METHODS count_table
      IMPORTING iv_table        TYPE tabname
      RETURNING VALUE(rv_count) TYPE i.
ENDCLASS.

CLASS zcl_crw_selfcheck IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    DATA lt_tables    TYPE STANDARD TABLE OF tabname WITH EMPTY KEY.
    DATA lv_rows      TYPE i.
    DATA lv_intervals TYPE i.
    DATA lv_version   TYPE zcrw_version-version_no.
    DATA lv_messages  TYPE i.
    DATA lv_roles     TYPE i.
    DATA lv_approvals TYPE i.
    DATA lv_icf       TYPE i.
    DATA lv_cts       TYPE i.
    DATA lv_icf_state TYPE string.
    DATA lv_cts_state TYPE string.
    DATA lv_failures  TYPE string.

    lt_tables = VALUE #( ( 'ZCRW_REQ' ) ( 'ZCRW_CD' ) ( 'ZCRW_TASK' ) ( 'ZCRW_TR' )
                         ( 'ZCRW_SCHED' ) ( 'ZCRW_APPR' ) ( 'ZCRW_HIST' ) ( 'ZCRW_NOTE' )
                         ( 'ZCRW_CYCLE' ) ( 'ZCRW_ROLE' ) ( 'ZCRW_APPR_CFG' )
                         ( 'ZCRW_VERSION' ) ( 'ZCRW_LOG' ) ).

*   Every application table must be readable.
    LOOP AT lt_tables ASSIGNING FIELD-SYMBOL(<lv_table>).
      lv_rows = lv_rows + count_table( <lv_table> ).
    ENDLOOP.

*   Number range intervals for all three business objects.
    SELECT COUNT(*)
      FROM nriv
      WHERE object    IN ( 'ZCRW_REQ', 'ZCRW_CD', 'ZCRW_TASK' )
        AND subobject = @space
        AND nrrangenr = '01'
      INTO @lv_intervals.

*   Latest component version and seed configuration.
    SELECT MAX( version_no )
      FROM zcrw_version
      WHERE component = 'CRW'
      INTO @lv_version.

    SELECT COUNT(*)
      FROM t100
      WHERE arbgb = 'ZCRW_MSG'
      INTO @lv_messages.

    SELECT COUNT(*)
      FROM zcrw_role
      WHERE role = 'ADMIN'
      INTO @lv_roles.

    SELECT COUNT(*)
      FROM zcrw_appr_cfg
      INTO @lv_approvals.

*   ICF node must exist: the SICF object is registered in TADIR.
    SELECT COUNT(*)
      FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SICF' AND obj_name LIKE 'ZCRW%'
      INTO @lv_icf.

    IF lv_icf > 0.
      lv_icf_state = 'OK'.
    ELSE.
      lv_icf_state = 'MISSING'.
    ENDIF.

*   CTS tables stay read-only; failures degrade but do not block the check.
    TRY.
        SELECT COUNT(*) FROM e070 INTO @lv_cts.
        lv_cts_state = 'OK'.
      CATCH cx_root.
        lv_cts_state = 'DEGRADED'.
    ENDTRY.

    IF lv_intervals <> 3.
      lv_failures = |{ lv_failures } intervals={ lv_intervals }|.
    ENDIF.
    IF lv_version IS INITIAL.
      lv_failures = |{ lv_failures } version-missing|.
    ENDIF.
    IF lv_messages = 0.
      lv_failures = |{ lv_failures } messages-missing|.
    ENDIF.
    IF lv_roles = 0.
      lv_failures = |{ lv_failures } admin-role-missing|.
    ENDIF.
    IF lv_approvals = 0.
      lv_failures = |{ lv_failures } approval-missing|.
    ENDIF.
    IF lv_icf = 0.
      lv_failures = |{ lv_failures } icf-missing|.
    ENDIF.

    IF lv_failures IS INITIAL.
      out->write( |CRW_SELFCHECK_OK tables=13 rows={ lv_rows } intervals={ lv_intervals }| &&
                  | version={ lv_version } messages={ lv_messages } roles={ lv_roles }| &&
                  | approvals={ lv_approvals } icf={ lv_icf_state } cts={ lv_cts_state }| ).
    ELSE.
      out->write( |CRW_SELFCHECK_FAIL{ lv_failures }| ).
    ENDIF.
  ENDMETHOD.

  METHOD count_table.
    DATA lv_table TYPE tabname.

    lv_table = iv_table.
    SELECT COUNT(*) FROM (lv_table) INTO @rv_count.
  ENDMETHOD.
ENDCLASS.
