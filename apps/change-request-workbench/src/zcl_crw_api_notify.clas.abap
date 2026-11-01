CLASS zcl_crw_api_notify DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_unread,
             count TYPE i,
           END OF ty_unread.

    TYPES: BEGIN OF ty_refresh,
             created TYPE i,
             unread  TYPE i,
           END OF ty_refresh.

    TYPES: BEGIN OF ty_read,
             id     TYPE string,
             status TYPE string,
             unread TYPE i,
           END OF ty_read.

    TYPES: BEGIN OF ty_read_all,
             updated TYPE i,
             unread  TYPE i,
           END OF ty_read_all.

    CLASS-METHODS list_notifications
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS unread
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context.

    CLASS-METHODS refresh
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS mark_one
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_id     TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS mark_all
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS require_method
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_method TYPE string
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_api_notify IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 1 OR it_segments[ 1 ] <> 'notifications'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown notification path'.
    ENDIF.

*   /notifications — list
    IF lines( it_segments ) = 1.
      require_method( io_ctx = io_ctx iv_method = 'GET' ).
      list_notifications( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lv_id = 'unread-count'.
      require_method( io_ctx = io_ctx iv_method = 'GET' ).
      unread( io_ctx ).
      RETURN.
    ENDIF.

    IF lv_id = 'refresh'.
      require_method( io_ctx = io_ctx iv_method = 'POST' ).
      refresh( io_ctx ).
      RETURN.
    ENDIF.

    IF lv_id = 'read-all'.
      require_method( io_ctx = io_ctx iv_method = 'POST' ).
      mark_all( io_ctx ).
      RETURN.
    ENDIF.

*   /notifications/{id}/read — mark one as read
    IF lines( it_segments ) >= 3.
      lv_sub = it_segments[ 3 ].
      IF lv_sub = 'read'.
        require_method( io_ctx = io_ctx iv_method = 'POST' ).
        mark_one( io_ctx = io_ctx iv_id = lv_id ).
        RETURN.
      ENDIF.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_crw_error
      EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown notification path'.
  ENDMETHOD.

  METHOD list_notifications.
    DATA lv_status TYPE string.
    DATA lv_type TYPE string.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA ls_result TYPE zcl_crw_notify=>ty_list.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_notifications.

    lv_status = to_upper( io_ctx->param( 'status' ) ).
    IF lv_status IS INITIAL.
      lv_status = 'ALL'.
    ENDIF.
    lv_type = to_upper( io_ctx->param( 'type' ) ).
    lv_page = io_ctx->param_int( iv_name = 'page' iv_default = 1 ).
    lv_size = io_ctx->param_int( iv_name = 'size' iv_default = 20 ).

    ls_result = zcl_crw_notify=>list_for_user( iv_user      = io_ctx->mv_user
                                               iv_status    = lv_status
                                               iv_type      = lv_type
                                               iv_page      = lv_page
                                               iv_page_size = lv_size ).

    LOOP AT ls_result-items ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND zcl_crw_api_map=>notification( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items     = lt_dto
                       iv_page      = lv_page
                       iv_page_size = lv_size
                       iv_total     = ls_result-total ).
  ENDMETHOD.

  METHOD unread.
    DATA ls_unread TYPE ty_unread.

    ls_unread-count = zcl_crw_notify=>unread_count( io_ctx->mv_user ).
    io_ctx->set_data( ls_unread ).
  ENDMETHOD.

  METHOD refresh.
    DATA ls_refresh TYPE ty_refresh.

    ls_refresh-created = zcl_crw_notify=>refresh_for_user( io_ctx->mv_user ).
    COMMIT WORK AND WAIT.
    ls_refresh-unread = zcl_crw_notify=>unread_count( io_ctx->mv_user ).
    io_ctx->set_data( ls_refresh ).
  ENDMETHOD.

  METHOD mark_one.
    DATA ls_read TYPE ty_read.

    ls_read-id = iv_id.
    zcl_crw_notify=>mark_read( iv_user = io_ctx->mv_user iv_notify_id = iv_id ).
    COMMIT WORK AND WAIT.
    ls_read-status = zcl_crw_notify=>gc_status_read.
    ls_read-unread = zcl_crw_notify=>unread_count( io_ctx->mv_user ).
    io_ctx->set_data( ls_read ).
  ENDMETHOD.

  METHOD mark_all.
    DATA ls_read_all TYPE ty_read_all.

    ls_read_all-updated = zcl_crw_notify=>mark_all_read( io_ctx->mv_user ).
    COMMIT WORK AND WAIT.
    ls_read_all-unread = zcl_crw_notify=>unread_count( io_ctx->mv_user ).
    io_ctx->set_data( ls_read_all ).
  ENDMETHOD.

  METHOD require_method.
    IF io_ctx->mv_method <> iv_method.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR'
                  iv_text = |Method { io_ctx->mv_method } is not supported for this notification path|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
