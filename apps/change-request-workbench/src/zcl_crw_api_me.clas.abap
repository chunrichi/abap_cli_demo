CLASS zcl_crw_api_me DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CLASS-METHODS get_me
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_health
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_dashboard
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS component_status
      IMPORTING iv_count       TYPE i
      RETURNING VALUE(rv_status) TYPE string.

    CLASS-METHODS version
      RETURNING VALUE(rv_version) TYPE string.
ENDCLASS.

CLASS zcl_crw_api_me IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_resource TYPE string.

    IF lines( it_segments ) < 1.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = it_segments[ 1 ].

    CASE lv_resource.
      WHEN 'me'.
        get_me( io_ctx ).
      WHEN 'health'.
        get_health( io_ctx ).
      WHEN 'dashboard'.
        get_dashboard( io_ctx ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDCASE.
  ENDMETHOD.

  METHOD get_me.
    DATA ls_me TYPE zcl_crw_api_types=>ty_me.
    DATA lv_index TYPE i.

    ls_me-user = io_ctx->mv_user.
    ls_me-environment = 'SAP_SYSTEM'.
    ls_me-version = version( ).
    ls_me-admin = zcl_crw_auth=>is_admin( io_ctx->mt_roles ).

    LOOP AT io_ctx->mt_roles ASSIGNING FIELD-SYMBOL(<ls_role>).
      lv_index = lv_index + 1.
      APPEND VALUE #( role       = <ls_role>-role
                      scope_type = <ls_role>-scope_type
                      scope_id   = <ls_role>-scope_id ) TO ls_me-roles.
    ENDLOOP.

    io_ctx->set_data( ls_me ).
  ENDMETHOD.

  METHOD get_health.
    DATA ls_health TYPE zcl_crw_api_types=>ty_health.
    DATA lv_count TYPE i.
    DATA lv_component TYPE zcrw_version-component.
    DATA lv_service TYPE string.

    ls_health-version = version( ).
    ls_health-components-version = 'ok'.

*   Data tables: a readable version row proves the core schema is installed.
    lv_component = 'CRW'.
    SELECT COUNT(*) FROM zcrw_version WHERE component = @lv_component INTO @lv_count.
    ls_health-components-tables = component_status( lv_count ).

*   Number ranges: three intervals are seeded by the bootstrap.
    SELECT COUNT(*) FROM nriv WHERE object LIKE 'ZCRW_%' INTO @lv_count.
    ls_health-components-number_ranges = component_status( lv_count ).

*   Approval matrix seed rows.
    SELECT COUNT(*) FROM zcrw_appr_cfg INTO @lv_count.
    ls_health-components-approval_matrix = component_status( lv_count ).

*   ICF node: this response is served through the ICF handler, so the node
*   and the handler wiring are proven by the request itself.
    ls_health-components-icf = 'ok'.

*   CTS read path (read-only); degradation does not block the workbench.
    TRY.
        SELECT COUNT(*) FROM e070 INTO @lv_count.
        ls_health-components-cts = COND #( WHEN lv_count > 0 THEN 'ok' ELSE 'degraded' ).
      CATCH cx_root.
        ls_health-components-cts = 'degraded'.
    ENDTRY.

    IF ls_health-components-tables = 'ok'
        AND ls_health-components-number_ranges = 'ok'
        AND ls_health-components-approval_matrix = 'ok'.
      ls_health-status = 'ok'.
    ELSE.
      ls_health-status = 'degraded'.
    ENDIF.

    io_ctx->set_data( ls_health ).
  ENDMETHOD.

  METHOD get_dashboard.
    DATA ls_dashboard TYPE zcl_crw_api_types=>ty_dashboard.
    DATA lv_user TYPE zcrw_appr-approver.
    DATA lv_assignee TYPE zcrw_task-assignee.
    DATA lv_count TYPE i.
    DATA lv_now TYPE char14.
    DATA lt_history TYPE zcl_crw_audit=>tt_history.
    DATA lv_display TYPE string.
    DATA lv_title TYPE string.

    lv_user = io_ctx->mv_user.
    lv_assignee = io_ctx->mv_user.
    lv_now = zcl_crw_util=>now( ).

    SELECT COUNT(*) FROM zcrw_appr
      WHERE approver = @lv_user AND appr_state = 'PENDING'
      INTO @lv_count.
    ls_dashboard-kpis-my_approvals = lv_count.

    SELECT COUNT(*) FROM zcrw_task
      WHERE assignee = @lv_assignee
        AND ( status = 'OPEN' OR status = 'IN_PROGRESS' )
      INTO @lv_count.
    ls_dashboard-kpis-my_tasks = lv_count.

    SELECT COUNT(*) FROM zcrw_req WHERE status = 'PENDING_APPROVAL' INTO @lv_count.
    ls_dashboard-kpis-pending_requests = lv_count.

    SELECT COUNT(*) FROM zcrw_cd WHERE status = 'IN_DEV' INTO @lv_count.
    ls_dashboard-kpis-in_dev = lv_count.

    SELECT COUNT(*) FROM zcrw_cd
      WHERE status = 'READY_TO_IMPORT' OR status = 'IMPORT_SCHEDULED'
      INTO @lv_count.
    ls_dashboard-kpis-ready_to_import = lv_count.

    SELECT COUNT(*) FROM zcrw_sched
      WHERE status = 'PLANNED' AND scheduled_at < @lv_now
      INTO @lv_count.
    ls_dashboard-kpis-overdue = lv_count.

    lt_history = zcl_crw_audit=>recent( iv_size = 20 ).
    LOOP AT lt_history ASSIGNING FIELD-SYMBOL(<ls_hist>).
      lv_title = ''.
      IF <ls_hist>-object_type = 'REQ'.
        SELECT SINGLE title FROM zcrw_req WHERE req_id = @<ls_hist>-object_id INTO @lv_title.
      ELSEIF <ls_hist>-object_type = 'CD'.
        SELECT SINGLE title FROM zcrw_cd WHERE cd_id = @<ls_hist>-object_id INTO @lv_title.
      ELSEIF <ls_hist>-object_type = 'TASK'.
        SELECT SINGLE title FROM zcrw_task WHERE task_id = @<ls_hist>-object_id INTO @lv_title.
      ENDIF.
      lv_display = zcl_crw_api_map=>display_id( iv_object_type = CONV string( <ls_hist>-object_type )
                                                iv_object_id   = CONV string( <ls_hist>-object_id ) ).
      APPEND VALUE #( object_type = <ls_hist>-object_type
                      object_id   = <ls_hist>-object_id
                      display_id  = lv_display
                      title       = lv_title
                      action      = <ls_hist>-action
                      changed_at  = zcl_crw_json=>format_timestamp( <ls_hist>-changed_at )
                      changed_by  = <ls_hist>-changed_by ) TO ls_dashboard-recent.
    ENDLOOP.

    io_ctx->set_data( ls_dashboard ).
  ENDMETHOD.

  METHOD component_status.
    rv_status = COND #( WHEN iv_count > 0 THEN 'ok' ELSE 'missing' ).
  ENDMETHOD.

  METHOD version.
    DATA lv_version TYPE zcrw_version-version_no.
    DATA lv_component TYPE zcrw_version-component.

    lv_component = 'CRW'.
    SELECT MAX( version_no )
      FROM zcrw_version
      WHERE component = @lv_component
      INTO @lv_version.

    IF lv_version IS INITIAL.
      rv_version = '0.0.0'.
    ELSE.
      rv_version = lv_version.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
