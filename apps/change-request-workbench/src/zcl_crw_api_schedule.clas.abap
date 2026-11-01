CLASS zcl_crw_api_schedule DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             action       TYPE string,
             scheduled_at TYPE string,
             note         TYPE string,
           END OF ty_body.

    CLASS-METHODS list_schedules
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS action_schedule
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_sched_id TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS read_body
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rs_body) TYPE ty_body.

    CLASS-METHODS page_params
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      EXPORTING ev_page TYPE i
                ev_size TYPE i.

    CLASS-METHODS slice_count
      IMPORTING iv_total       TYPE i
                iv_page        TYPE i
                iv_size        TYPE i
      RETURNING VALUE(rv_count) TYPE i.
ENDCLASS.

CLASS zcl_crw_api_schedule IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 2.
      IF io_ctx->mv_method <> 'GET'.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed'.
      ENDIF.
      list_schedules( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].
    IF lines( it_segments ) >= 3.
      lv_sub = it_segments[ 3 ].
      IF lv_sub = 'actions'.
        action_schedule( io_ctx = io_ctx iv_sched_id = lv_id ).
        RETURN.
      ENDIF.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_crw_error
      EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown schedule path'.
  ENDMETHOD.

  METHOD list_schedules.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lv_from_date TYPE dats.
    DATA lv_to_date TYPE dats.
    DATA lt_rows TYPE zcl_crw_schedule_svc=>tt_schedules.
    DATA lt_dto TYPE STANDARD TABLE OF zcl_crw_api_types=>ty_schedule WITH EMPTY KEY.
    DATA lv_overdue_only TYPE abap_bool.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).

    lv_from_date = zcl_crw_json=>parse_date( io_ctx->param( 'from' ) ).
    lv_to_date = zcl_crw_json=>parse_date( io_ctx->param( 'to' ) ).
    lv_overdue_only = xsdbool( to_lower( io_ctx->param( 'overdue' ) ) = 'true' ).

    lt_rows = zcl_crw_schedule_svc=>list( iv_from        = lv_from_date
                                           iv_to          = lv_to_date
                                           iv_target_sys  = io_ctx->param( 'targetSystem' )
                                           iv_status      = io_ctx->param( 'status' )
                                           iv_object_type = io_ctx->param( 'objectType' ) ).

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      DATA(ls_dto) = zcl_crw_api_map=>import_schedule( <ls_row> ).
      IF lv_overdue_only = abap_true AND ls_dto-overdue = abap_false.
        CONTINUE.
      ENDIF.
      APPEND ls_dto TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD action_schedule.
    DATA ls_body TYPE ty_body.
    DATA ls_row TYPE zcrw_sched.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_schedule.
    DATA lv_planned TYPE char14.

    ls_body = read_body( io_ctx ).
    ls_row = zcl_crw_schedule_svc=>get( CONV zcrw_sched-sched_id( iv_sched_id ) ).

    CASE to_upper( ls_body-action ).
      WHEN 'RESCHEDULE'.
        lv_planned = zcl_crw_json=>parse_timestamp( ls_body-scheduled_at ).
        IF lv_planned IS INITIAL.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'scheduledAt is required'.
        ENDIF.
        zcl_crw_schedule_svc=>create_or_update( iv_object_type  = CONV string( ls_row-object_type )
                                                iv_object_id    = CONV string( ls_row-object_id )
                                                iv_target_sys   = CONV string( ls_row-target_sys )
                                                iv_scheduled_at = lv_planned
                                                iv_note         = ls_body-note ).
      WHEN 'CANCEL'.
        zcl_crw_schedule_svc=>cancel( iv_sched_id = ls_row-sched_id iv_note = ls_body-note ).
      WHEN 'CONFIRM'.
        zcl_crw_schedule_svc=>confirm( iv_sched_id = ls_row-sched_id iv_note = ls_body-note ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'action must be RESCHEDULE, CANCEL or CONFIRM'.
    ENDCASE.

    ls_row = zcl_crw_schedule_svc=>get( CONV zcrw_sched-sched_id( iv_sched_id ) ).
    ls_dto = zcl_crw_api_map=>import_schedule( ls_row ).
    io_ctx->set_data( ls_dto ).
  ENDMETHOD.

  METHOD read_body.
    zcl_crw_json=>deserialize( EXPORTING iv_json = io_ctx->mv_body CHANGING cs_data = rs_body ).
  ENDMETHOD.

  METHOD page_params.
    ev_page = io_ctx->param_int( iv_name = 'page' iv_default = 1 ).
    IF ev_page < 1.
      ev_page = 1.
    ENDIF.
    ev_size = io_ctx->param_int( iv_name = 'size' iv_default = 50 ).
    IF ev_size < 1.
      ev_size = 50.
    ENDIF.
    IF ev_size > 200.
      ev_size = 200.
    ENDIF.
  ENDMETHOD.

  METHOD slice_count.
    DATA lv_rest TYPE i.

    IF iv_page < 1 OR iv_size < 1.
      rv_count = 0.
      RETURN.
    ENDIF.

    lv_rest = iv_total - ( iv_page - 1 ) * iv_size.
    IF lv_rest <= 0.
      rv_count = 0.
    ELSE.
      rv_count = nmin( val1 = iv_size val2 = lv_rest ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
