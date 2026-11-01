CLASS zcl_crw_demo_data DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CLASS-METHODS seed
      RETURNING VALUE(rv_summary) TYPE string
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CONSTANTS: gc_requester TYPE zcrw_req-requester VALUE 'DEMO_REQ',
               gc_owner     TYPE zcrw_req-owner VALUE 'DEMO_OWNER',
               gc_developer TYPE zcrw_task-assignee VALUE 'DEMO_DEV',
               gc_tester    TYPE zcrw_task-assignee VALUE 'DEMO_TEST'.

    CLASS-METHODS submit_request
      IMPORTING iv_req_id  TYPE zcrw_req-req_id
                iv_approve TYPE abap_bool
      RAISING   zcx_crw_error.

    CLASS-METHODS start_and_close_task
      IMPORTING iv_task_id TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_demo_data IMPLEMENTATION.
  METHOD seed.
    DATA ls_req TYPE zcl_crw_request_svc=>ty_create_input.
    DATA ls_cd TYPE zcl_crw_cd_svc=>ty_create_input.
    DATA ls_task TYPE zcl_crw_task_svc=>ty_create_input.
    DATA lv_req_active TYPE zcrw_req-req_id.
    DATA lv_req_pending TYPE zcrw_req-req_id.
    DATA lv_req_draft TYPE zcrw_req-req_id.
    DATA lv_cd TYPE zcrw_cd-cd_id.
    DATA lv_task TYPE zcrw_task-task_id.
    DATA ls_row TYPE zcrw_req.
    DATA ls_cd_row TYPE zcrw_cd.
    DATA ls_sched TYPE zcrw_sched.
    DATA lv_planned TYPE char14.
    DATA lv_plan_day TYPE d.

*   Request A: urgent change in progress with a scheduled change document.
    ls_req-req_type = 'URG'.
    ls_req-title = '紧急修复：采购订单审批阈值调整'.
    ls_req-description = '修复采购订单审批阈值配置错误，影响 MM-PUR 流程。'.
    ls_req-priority = '1'.
    ls_req-component = 'MM-PUR'.
    ls_req-cycle_id = '2026-11'.
    ls_req-requester = gc_requester.
    ls_req-owner = gc_owner.
    ls_req-planned_start = sy-datum.
    ls_req-planned_end = sy-datum + 10.
    lv_req_active = zcl_crw_request_svc=>create( ls_req ).

    submit_request( iv_req_id = lv_req_active iv_approve = abap_true ).

*   Change document with one closed development task and one closed test task.
    ls_cd-req_id = lv_req_active.
    ls_cd-title = 'MM-PUR 审批阈值修复批次'.
    ls_cd-target_sys = 'QAS'.
    ls_cd-cycle_id = '2026-11'.
    ls_cd-owner = gc_owner.
    ls_cd-dev_lead = gc_developer.
    ls_cd-test_lead = gc_tester.
    lv_cd = zcl_crw_cd_svc=>create( ls_cd ).

    ls_row = zcl_crw_request_svc=>get( lv_req_active ).
    zcl_crw_request_svc=>action( iv_req_id = lv_req_active
                                 iv_action = 'START_PROGRESS'
                                 iv_version = CONV i( ls_row-version ) ).

    ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
    zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                            iv_action = 'START_DEV'
                            iv_version = CONV i( ls_cd_row-version ) ).

    ls_task-cd_id = lv_cd.
    ls_task-req_id = lv_req_active.
    ls_task-task_type = 'DEV'.
    ls_task-title = '调整审批阈值配置'.
    ls_task-assignee = gc_developer.
    ls_task-est_hours = '00008'.
    lv_task = zcl_crw_task_svc=>create( ls_task ).
    start_and_close_task( lv_task ).

    ls_task-task_type = 'TEST'.
    ls_task-title = '回归测试采购订单审批流程'.
    ls_task-assignee = gc_tester.
    ls_task-est_hours = '00004'.
    lv_task = zcl_crw_task_svc=>create( ls_task ).
    start_and_close_task( lv_task ).

    ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
    zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                            iv_action = 'SUBMIT_TEST'
                            iv_version = CONV i( ls_cd_row-version ) ).

    ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
    zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                            iv_action = 'PASS_TEST'
                            iv_version = CONV i( ls_cd_row-version )
                            iv_comment = '回归测试通过（演示数据）' ).

    ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
    zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                            iv_action = 'SUBMIT_APPROVAL'
                            iv_version = CONV i( ls_cd_row-version ) ).

    ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
    IF ls_cd_row-approval_state = zcl_crw_cd_svc=>gc_approval_ok.
      zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                              iv_action = 'MARK_READY'
                              iv_version = CONV i( ls_cd_row-version ) ).

      lv_plan_day = sy-datum + 3.
      lv_planned = |{ CONV string( lv_plan_day ) }220000|.
      ls_cd_row = zcl_crw_cd_svc=>get( lv_cd ).
      zcl_crw_cd_svc=>action( iv_cd_id = lv_cd
                              iv_action = 'SCHEDULE_IMPORT'
                              iv_version = CONV i( ls_cd_row-version )
                              iv_planned_import_at = zcl_crw_json=>format_timestamp( lv_planned )
                              iv_comment = '计划于发布窗口导入 QAS（演示数据）' ).
      ls_sched = zcl_crw_schedule_svc=>active_for_object( iv_object_type = 'CD'
                                                          iv_object_id   = CONV string( lv_cd ) ).
    ENDIF.

*   Request B: standard change waiting for approval.
    ls_req-req_type = 'STD'.
    ls_req-title = '新增供应商主数据校验规则'.
    ls_req-description = '在供应商主数据保存时增加银行账号格式校验。'.
    ls_req-priority = '3'.
    ls_req-component = 'MM-PUR'.
    ls_req-cycle_id = '2026-11'.
    ls_req-requester = gc_requester.
    ls_req-owner = gc_owner.
    lv_req_pending = zcl_crw_request_svc=>create( ls_req ).
    submit_request( iv_req_id = lv_req_pending iv_approve = abap_false ).

*   Request C: draft.
    ls_req-req_type = 'STD'.
    ls_req-title = '报表权限口径梳理'.
    ls_req-description = '梳理采购报表权限口径，待补充影响范围。'.
    ls_req-priority = '4'.
    ls_req-component = 'MM-REP'.
    ls_req-requester = gc_requester.
    ls_req-owner = gc_requester.
    lv_req_draft = zcl_crw_request_svc=>create( ls_req ).

*   Collaboration notes on the active request.
    zcl_crw_request_svc=>notes_add( iv_req_id = lv_req_active
                                    iv_text = '已与业务确认影响范围：仅 MM-PUR 审批阈值。' ).
    zcl_crw_request_svc=>notes_add( iv_req_id = lv_req_active
                                    iv_text = 'QAS 验证通过，等待发布窗口。' ).

    rv_summary = |requests=3 cds=1 tasks=2 schedules={ COND i( WHEN ls_sched-sched_id IS NOT INITIAL THEN 1 ELSE 0 ) }|.
  ENDMETHOD.

  METHOD submit_request.
    DATA ls_row TYPE zcrw_req.
    DATA lv_appr TYPE string.

    ls_row = zcl_crw_request_svc=>get( iv_req_id ).
    zcl_crw_request_svc=>action( iv_req_id = iv_req_id
                                 iv_action = 'SUBMIT'
                                 iv_version = CONV i( ls_row-version ) ).

*   Approve the CR when the matrix generated a step for the current user.
    IF iv_approve = abap_false.
      RETURN.
    ENDIF.

    ls_row = zcl_crw_request_svc=>get( iv_req_id ).
    IF ls_row-status = 'PENDING_APPROVAL'.
      lv_appr = zcl_crw_appr_svc=>current_step_for_user( iv_object_type = 'REQ'
                                                         iv_object_id   = CONV string( iv_req_id )
                                                         iv_user        = CONV string( sy-uname ) ).
      IF lv_appr IS NOT INITIAL.
        zcl_crw_appr_svc=>decide( iv_appr_id = lv_appr
                                  iv_user = CONV string( sy-uname )
                                  iv_decision = 'APPROVED'
                                  iv_comment = '演示数据：审批通过'
                                  iv_version = CONV i( ls_row-version ) ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD start_and_close_task.
    DATA ls_task TYPE zcrw_task.

    ls_task = zcl_crw_task_svc=>get( iv_task_id ).
    zcl_crw_task_svc=>action( iv_task_id = iv_task_id
                              iv_action = 'START'
                              iv_version = CONV i( ls_task-version ) ).

    ls_task = zcl_crw_task_svc=>get( iv_task_id ).
    zcl_crw_task_svc=>action( iv_task_id = iv_task_id
                              iv_action = 'DONE'
                              iv_version = CONV i( ls_task-version ) ).
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    TRY.
        DATA(lv_summary) = seed( ).
        out->write( |CRW_DEMO_DATA_OK { lv_summary }| ).
      CATCH zcx_crw_error INTO DATA(lx_error).
        out->write( |CRW_DEMO_DATA_FAIL { lx_error->mv_code } { lx_error->mv_text }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
