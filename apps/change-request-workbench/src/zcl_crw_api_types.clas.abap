CLASS zcl_crw_api_types DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
*   Identity and health.
    TYPES: BEGIN OF ty_role,
             role       TYPE string,
             scope_type TYPE string,
             scope_id   TYPE string,
           END OF ty_role.
    TYPES tt_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_me,
             user         TYPE string,
             display_name TYPE string,
             roles        TYPE tt_roles,
             admin        TYPE abap_bool,
             environment  TYPE string,
             version      TYPE string,
           END OF ty_me.

    TYPES: BEGIN OF ty_health_components,
             icf             TYPE string,
             tables          TYPE string,
             number_ranges   TYPE string,
             approval_matrix TYPE string,
             cts             TYPE string,
             version         TYPE string,
           END OF ty_health_components.

    TYPES: BEGIN OF ty_health,
             version    TYPE string,
             status     TYPE string,
             components TYPE ty_health_components,
           END OF ty_health.

*   Dashboard.
    TYPES: BEGIN OF ty_kpis,
             my_approvals     TYPE i,
             my_tasks         TYPE i,
             pending_requests TYPE i,
             in_dev           TYPE i,
             ready_to_import  TYPE i,
             overdue          TYPE i,
           END OF ty_kpis.

    TYPES: BEGIN OF ty_recent,
             object_type TYPE string,
             object_id   TYPE string,
             display_id  TYPE string,
             title       TYPE string,
             action      TYPE string,
             changed_at  TYPE string,
             changed_by  TYPE string,
           END OF ty_recent.
    TYPES tt_recent TYPE STANDARD TABLE OF ty_recent WITH EMPTY KEY.

    TYPES: BEGIN OF ty_dashboard,
             kpis   TYPE ty_kpis,
             recent TYPE tt_recent,
           END OF ty_dashboard.

*   Change request.
    TYPES: BEGIN OF ty_request,
             id             TYPE string,
             display_id     TYPE string,
             request_type   TYPE string,
             title          TYPE string,
             description    TYPE string,
             status         TYPE string,
             priority       TYPE string,
             component      TYPE string,
             cycle_id       TYPE string,
             requester      TYPE string,
             owner          TYPE string,
             approval_state TYPE string,
             planned_start  TYPE string,
             planned_end    TYPE string,
             due_date       TYPE string,
             version        TYPE i,
             created_at     TYPE string,
             created_by     TYPE string,
             changed_at     TYPE string,
             changed_by     TYPE string,
             closed_at      TYPE string,
             cancel_reason  TYPE string,
           END OF ty_request.
    TYPES tt_requests TYPE STANDARD TABLE OF ty_request WITH EMPTY KEY.

*   Change document.
    TYPES: BEGIN OF ty_cd,
             id                TYPE string,
             display_id        TYPE string,
             req_id            TYPE string,
             req_display_id    TYPE string,
             cycle_id          TYPE string,
             title             TYPE string,
             status            TYPE string,
             owner             TYPE string,
             dev_lead          TYPE string,
             test_lead         TYPE string,
             target_system     TYPE string,
             planned_import_at TYPE string,
             approval_state    TYPE string,
             version           TYPE i,
             created_at        TYPE string,
             created_by        TYPE string,
             changed_at        TYPE string,
             changed_by        TYPE string,
             closed_at         TYPE string,
           END OF ty_cd.
    TYPES tt_cds TYPE STANDARD TABLE OF ty_cd WITH EMPTY KEY.

*   Task and subtask.
    TYPES: BEGIN OF ty_task,
             id             TYPE string,
             display_id     TYPE string,
             req_id         TYPE string,
             cd_id          TYPE string,
             parent_task_id TYPE string,
             task_level     TYPE string,
             task_type      TYPE string,
             title          TYPE string,
             assignee       TYPE string,
             status         TYPE string,
             due_date       TYPE string,
             est_hours      TYPE i,
             version        TYPE i,
             created_at     TYPE string,
             created_by     TYPE string,
             changed_at     TYPE string,
             changed_by     TYPE string,
           END OF ty_task.
    TYPES tt_tasks TYPE STANDARD TABLE OF ty_task WITH EMPTY KEY.

*   Approval step.
    TYPES: BEGIN OF ty_approval,
             id               TYPE string,
             object_type      TYPE string,
             object_id        TYPE string,
             object_display_id TYPE string,
             object_title     TYPE string,
             step_no          TYPE i,
             approver         TYPE string,
             appr_state       TYPE string,
             decided_at       TYPE string,
             comment          TYPE string,
             created_at       TYPE string,
           END OF ty_approval.
    TYPES tt_approvals TYPE STANDARD TABLE OF ty_approval WITH EMPTY KEY.

*   In-app notification.
    TYPES: BEGIN OF ty_notification,
             id               TYPE string,
             notify_type      TYPE string,
             object_type      TYPE string,
             object_id        TYPE string,
             object_display_id TYPE string,
             title            TYPE string,
             message          TYPE string,
             link_page        TYPE string,
             severity         TYPE string,
             status           TYPE string,
             created_at       TYPE string,
             read_at          TYPE string,
           END OF ty_notification.
    TYPES tt_notifications TYPE STANDARD TABLE OF ty_notification WITH EMPTY KEY.

*   Transport.
    TYPES: BEGIN OF ty_transport_object,
             pgmid         TYPE string,
             object        TYPE string,
             obj_name      TYPE string,
             obj_type      TYPE string,
             obj_name_text TYPE string,
           END OF ty_transport_object.
    TYPES tt_transport_objects TYPE STANDARD TABLE OF ty_transport_object WITH EMPTY KEY.

    TYPES: BEGIN OF ty_transport,
             trkorr              TYPE string,
             cd_id               TYPE string,
             task_id             TYPE string,
             tr_kind             TYPE string,
             target_system       TYPE string,
             tr_status           TYPE string,
             tr_status_text      TYPE string,
             released_at         TYPE string,
             import_scheduled_at TYPE string,
             imported_at         TYPE string,
             last_sync_at        TYPE string,
             linked_at           TYPE string,
             linked_by           TYPE string,
             retrofit_state      TYPE string,
             sync_state          TYPE string,
             description         TYPE string,
             linked              TYPE abap_bool,
             degraded            TYPE abap_bool,
           END OF ty_transport.

    TYPES tt_transports TYPE STANDARD TABLE OF ty_transport WITH EMPTY KEY.

    TYPES: BEGIN OF ty_transport_detail,
             trkorr              TYPE string,
             cd_id               TYPE string,
             task_id             TYPE string,
             tr_kind             TYPE string,
             target_system       TYPE string,
             tr_status           TYPE string,
             tr_status_text      TYPE string,
             released_at         TYPE string,
             import_scheduled_at TYPE string,
             imported_at         TYPE string,
             last_sync_at        TYPE string,
             linked_at           TYPE string,
             linked_by           TYPE string,
             retrofit_state      TYPE string,
             sync_state          TYPE string,
             description         TYPE string,
             linked              TYPE abap_bool,
             degraded            TYPE abap_bool,
             objects             TYPE tt_transport_objects,
           END OF ty_transport_detail.

*   Import schedule.
    TYPES: BEGIN OF ty_schedule,
             id               TYPE string,
             object_type      TYPE string,
             object_id        TYPE string,
             object_display_id TYPE string,
             target_system    TYPE string,
             scheduled_at     TYPE string,
             status           TYPE string,
             note             TYPE string,
             overdue          TYPE abap_bool,
           END OF ty_schedule.
    TYPES tt_schedules TYPE STANDARD TABLE OF ty_schedule WITH EMPTY KEY.

*   History and note.
    TYPES: BEGIN OF ty_history,
             id          TYPE string,
             object_type TYPE string,
             object_id   TYPE string,
             action      TYPE string,
             field       TYPE string,
             old_value   TYPE string,
             new_value   TYPE string,
             comment     TYPE string,
             changed_by  TYPE string,
             changed_at  TYPE string,
             source      TYPE string,
           END OF ty_history.
    TYPES tt_history TYPE STANDARD TABLE OF ty_history WITH EMPTY KEY.

    TYPES: BEGIN OF ty_note,
             id          TYPE string,
             object_type TYPE string,
             object_id   TYPE string,
             author      TYPE string,
             text        TYPE string,
             created_at  TYPE string,
             visibility  TYPE string,
           END OF ty_note.
    TYPES tt_notes TYPE STANDARD TABLE OF ty_note WITH EMPTY KEY.

*   Configuration rows.
    TYPES: BEGIN OF ty_cycle,
             id            TYPE string,
             description   TYPE string,
             start_date    TYPE string,
             end_date      TYPE string,
             freeze_date   TYPE string,
             status        TYPE string,
             target_system TYPE string,
           END OF ty_cycle.
    TYPES tt_cycles TYPE STANDARD TABLE OF ty_cycle WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role_row,
             user_id    TYPE string,
             role       TYPE string,
             scope_type TYPE string,
             scope_id   TYPE string,
             valid_from TYPE string,
             valid_to   TYPE string,
           END OF ty_role_row.
    TYPES tt_role_rows TYPE STANDARD TABLE OF ty_role_row WITH EMPTY KEY.

    TYPES: BEGIN OF ty_matrix_row,
             profile_id    TYPE string,
             step_no       TYPE i,
             approver_role TYPE string,
             approver_user TYPE string,
             object_type   TYPE string,
             req_type      TYPE string,
             priority      TYPE string,
             mandatory     TYPE string,
           END OF ty_matrix_row.
    TYPES tt_matrix_rows TYPE STANDARD TABLE OF ty_matrix_row WITH EMPTY KEY.
ENDCLASS.

CLASS zcl_crw_api_types IMPLEMENTATION.
ENDCLASS.
