CLASS zcl_crw_api_map DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS request
      IMPORTING is_row       TYPE zcrw_req
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_request.

    CLASS-METHODS change_document
      IMPORTING is_row       TYPE zcrw_cd
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_cd.

    CLASS-METHODS task
      IMPORTING is_row       TYPE zcrw_task
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_task.

    CLASS-METHODS approval
      IMPORTING is_row        TYPE zcrw_appr
                iv_display_id TYPE string
                iv_title      TYPE string
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_approval.

    CLASS-METHODS history
      IMPORTING is_row       TYPE zcrw_hist
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_history.

    CLASS-METHODS note
      IMPORTING is_row       TYPE zcrw_note
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_note.

    CLASS-METHODS import_schedule
      IMPORTING is_row       TYPE zcrw_sched
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_schedule.

    CLASS-METHODS cycle
      IMPORTING is_row       TYPE zcrw_cycle
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_cycle.

    CLASS-METHODS role_row
      IMPORTING is_row       TYPE zcrw_role
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_role_row.

    CLASS-METHODS matrix_row
      IMPORTING is_row       TYPE zcrw_appr_cfg
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_matrix_row.

    CLASS-METHODS notification
      IMPORTING is_row       TYPE zcrw_notify
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_notification.

    CLASS-METHODS transport
      IMPORTING is_row       TYPE zcrw_tr
      RETURNING VALUE(rs_dto) TYPE zcl_crw_api_types=>ty_transport.

    CLASS-METHODS display_id
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_id)   TYPE string.
ENDCLASS.

CLASS zcl_crw_api_map IMPLEMENTATION.
  METHOD request.
    rs_dto-id             = is_row-req_id.
    rs_dto-display_id     = display_id( iv_object_type = 'REQ' iv_object_id = CONV string( is_row-req_id ) ).
    rs_dto-request_type   = is_row-req_type.
    rs_dto-title          = is_row-title.
    rs_dto-description    = is_row-description.
    rs_dto-status         = is_row-status.
    rs_dto-priority       = is_row-priority.
    rs_dto-component      = is_row-component.
    rs_dto-cycle_id       = is_row-cycle_id.
    rs_dto-requester      = is_row-requester.
    rs_dto-owner          = is_row-owner.
    rs_dto-approval_state = is_row-approval_state.
    rs_dto-planned_start  = zcl_crw_json=>format_date( is_row-planned_start ).
    rs_dto-planned_end    = zcl_crw_json=>format_date( is_row-planned_end ).
    rs_dto-due_date       = zcl_crw_json=>format_date( is_row-due_date ).
    rs_dto-version        = CONV i( is_row-version ).
    rs_dto-created_at     = zcl_crw_json=>format_timestamp( is_row-created_at ).
    rs_dto-created_by     = is_row-created_by.
    rs_dto-changed_at     = zcl_crw_json=>format_timestamp( is_row-changed_at ).
    rs_dto-changed_by     = is_row-changed_by.
    rs_dto-closed_at      = zcl_crw_json=>format_timestamp( is_row-closed_at ).
    rs_dto-cancel_reason  = is_row-cancel_reason.
  ENDMETHOD.

  METHOD change_document.
    rs_dto-id                = is_row-cd_id.
    rs_dto-display_id        = display_id( iv_object_type = 'CD' iv_object_id = CONV string( is_row-cd_id ) ).
    rs_dto-req_id            = is_row-req_id.
    rs_dto-req_display_id    = display_id( iv_object_type = 'REQ' iv_object_id = CONV string( is_row-req_id ) ).
    rs_dto-cycle_id          = is_row-cycle_id.
    rs_dto-title             = is_row-title.
    rs_dto-status            = is_row-status.
    rs_dto-owner             = is_row-owner.
    rs_dto-dev_lead          = is_row-dev_lead.
    rs_dto-test_lead         = is_row-test_lead.
    rs_dto-target_system     = is_row-target_sys.
    rs_dto-planned_import_at = zcl_crw_json=>format_timestamp( is_row-planned_import_at ).
    rs_dto-approval_state    = is_row-approval_state.
    rs_dto-version           = CONV i( is_row-version ).
    rs_dto-created_at        = zcl_crw_json=>format_timestamp( is_row-created_at ).
    rs_dto-created_by        = is_row-created_by.
    rs_dto-changed_at        = zcl_crw_json=>format_timestamp( is_row-changed_at ).
    rs_dto-changed_by        = is_row-changed_by.
    rs_dto-closed_at         = zcl_crw_json=>format_timestamp( is_row-closed_at ).
  ENDMETHOD.

  METHOD task.
    rs_dto-id             = is_row-task_id.
    rs_dto-display_id     = display_id( iv_object_type = 'TASK' iv_object_id = CONV string( is_row-task_id ) ).
    rs_dto-req_id         = is_row-req_id.
    rs_dto-cd_id          = is_row-cd_id.
    rs_dto-parent_task_id = is_row-parent_task_id.
    rs_dto-task_level     = is_row-task_level.
    rs_dto-task_type      = is_row-task_type.
    rs_dto-title          = is_row-title.
    rs_dto-assignee       = is_row-assignee.
    rs_dto-status         = is_row-status.
    rs_dto-due_date       = zcl_crw_json=>format_date( is_row-due_date ).
    rs_dto-est_hours      = CONV i( is_row-est_hours ).
    rs_dto-version        = CONV i( is_row-version ).
    rs_dto-created_at     = zcl_crw_json=>format_timestamp( is_row-created_at ).
    rs_dto-created_by     = is_row-created_by.
    rs_dto-changed_at     = zcl_crw_json=>format_timestamp( is_row-changed_at ).
    rs_dto-changed_by     = is_row-changed_by.
  ENDMETHOD.

  METHOD approval.
    rs_dto-id                = is_row-appr_id.
    rs_dto-object_type       = is_row-object_type.
    rs_dto-object_id         = is_row-object_id.
    rs_dto-object_display_id = iv_display_id.
    rs_dto-object_title      = iv_title.
    rs_dto-step_no           = CONV i( is_row-step_no ).
    rs_dto-approver          = is_row-approver.
    rs_dto-appr_state        = is_row-appr_state.
    rs_dto-decided_at        = zcl_crw_json=>format_timestamp( is_row-decided_at ).
    rs_dto-comment           = is_row-comment_txt.
    rs_dto-created_at        = zcl_crw_json=>format_timestamp( is_row-created_at ).
  ENDMETHOD.

  METHOD history.
    rs_dto-id          = is_row-hist_id.
    rs_dto-object_type = is_row-object_type.
    rs_dto-object_id   = is_row-object_id.
    rs_dto-action      = is_row-action.
    rs_dto-field       = is_row-field.
    rs_dto-old_value   = is_row-old_value.
    rs_dto-new_value   = is_row-new_value.
    rs_dto-comment     = is_row-comment_txt.
    rs_dto-changed_by  = is_row-changed_by.
    rs_dto-changed_at  = zcl_crw_json=>format_timestamp( is_row-changed_at ).
    rs_dto-source      = is_row-source.
  ENDMETHOD.

  METHOD note.
    rs_dto-id          = is_row-note_id.
    rs_dto-object_type = is_row-object_type.
    rs_dto-object_id   = is_row-object_id.
    rs_dto-author      = is_row-author.
    rs_dto-text        = is_row-text.
    rs_dto-created_at  = zcl_crw_json=>format_timestamp( is_row-created_at ).
    rs_dto-visibility  = is_row-visibility.
  ENDMETHOD.

  METHOD import_schedule.
    rs_dto-id            = is_row-sched_id.
    rs_dto-object_type   = is_row-object_type.
    rs_dto-object_id     = is_row-object_id.
    rs_dto-target_system = is_row-target_sys.
    rs_dto-scheduled_at  = zcl_crw_json=>format_timestamp( is_row-scheduled_at ).
    rs_dto-status        = is_row-status.
    rs_dto-note          = is_row-note.
    rs_dto-overdue       = COND #( WHEN is_row-status = 'PLANNED' AND is_row-scheduled_at IS NOT INITIAL
                                   THEN zcl_crw_schedule_svc=>is_overdue( is_row-scheduled_at )
                                   ELSE abap_false ).
    IF is_row-object_type = 'CD'.
      rs_dto-object_display_id = display_id( iv_object_type = 'CD' iv_object_id = CONV string( is_row-object_id ) ).
    ELSE.
      rs_dto-object_display_id = is_row-object_id.
    ENDIF.
  ENDMETHOD.

  METHOD cycle.
    rs_dto-id            = is_row-cycle_id.
    rs_dto-description   = is_row-description.
    rs_dto-start_date    = zcl_crw_json=>format_date( is_row-start_date ).
    rs_dto-end_date      = zcl_crw_json=>format_date( is_row-end_date ).
    rs_dto-freeze_date   = zcl_crw_json=>format_date( is_row-freeze_date ).
    rs_dto-status        = is_row-status.
    rs_dto-target_system = is_row-target_sys.
  ENDMETHOD.

  METHOD role_row.
    rs_dto-user_id    = is_row-user_id.
    rs_dto-role       = is_row-role.
    rs_dto-scope_type = is_row-scope_type.
    rs_dto-scope_id   = is_row-scope_id.
    rs_dto-valid_from = zcl_crw_json=>format_date( is_row-valid_from ).
    rs_dto-valid_to   = zcl_crw_json=>format_date( is_row-valid_to ).
  ENDMETHOD.

  METHOD matrix_row.
    rs_dto-profile_id    = is_row-profile_id.
    rs_dto-step_no       = CONV i( is_row-step_no ).
    rs_dto-approver_role = is_row-approver_role.
    rs_dto-approver_user = is_row-approver_user.
    rs_dto-object_type   = is_row-object_type.
    rs_dto-req_type      = is_row-req_type.
    rs_dto-priority      = is_row-priority.
    rs_dto-mandatory     = is_row-mandatory.
  ENDMETHOD.

  METHOD notification.
    rs_dto-id                = is_row-notify_id.
    rs_dto-notify_type       = is_row-notify_type.
    rs_dto-object_type       = is_row-object_type.
    rs_dto-object_id         = is_row-object_id.
    rs_dto-object_display_id = zcl_crw_notify=>object_display_id( iv_object_type = CONV string( is_row-object_type )
                                                                  iv_object_id   = CONV string( is_row-object_id ) ).
    rs_dto-title             = is_row-title.
    rs_dto-message           = is_row-message.
    rs_dto-link_page         = is_row-link_page.
    rs_dto-severity          = is_row-severity.
    rs_dto-status            = is_row-status.
    rs_dto-created_at        = zcl_crw_json=>format_timestamp( is_row-created_at ).
    rs_dto-read_at           = zcl_crw_json=>format_timestamp( is_row-read_at ).
  ENDMETHOD.

  METHOD transport.
    rs_dto-trkorr              = is_row-trkorr.
    rs_dto-cd_id               = is_row-cd_id.
    rs_dto-task_id             = is_row-task_id.
    rs_dto-tr_kind             = is_row-tr_kind.
    rs_dto-target_system       = is_row-tarsystem.
    rs_dto-tr_status           = is_row-tr_status.
    rs_dto-tr_status_text      = is_row-tr_status_txt.
    rs_dto-released_at         = zcl_crw_json=>format_timestamp( is_row-released_at ).
    rs_dto-import_scheduled_at = zcl_crw_json=>format_timestamp( is_row-import_scheduled_at ).
    rs_dto-imported_at         = zcl_crw_json=>format_timestamp( is_row-imported_at ).
    rs_dto-last_sync_at        = zcl_crw_json=>format_timestamp( is_row-last_sync_at ).
    rs_dto-linked_at           = zcl_crw_json=>format_timestamp( is_row-linked_at ).
    rs_dto-linked_by           = is_row-linked_by.
    rs_dto-retrofit_state      = is_row-retrofit_state.
    rs_dto-sync_state          = is_row-sync_state.
    rs_dto-description         = is_row-description.
    rs_dto-linked              = xsdbool( is_row-cd_id IS NOT INITIAL ).
    rs_dto-degraded            = xsdbool( is_row-sync_state = 'ERROR' ).
  ENDMETHOD.

  METHOD display_id.
    CASE iv_object_type.
      WHEN 'REQ'.
        rv_id = |CR-{ iv_object_id }|.
      WHEN 'CD'.
        rv_id = |CD-{ iv_object_id }|.
      WHEN 'TASK'.
        rv_id = |T-{ iv_object_id }|.
      WHEN OTHERS.
        rv_id = iv_object_id.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.
