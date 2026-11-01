CLASS zcl_crw_transport_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_transports TYPE STANDARD TABLE OF zcrw_tr WITH EMPTY KEY.

    CONSTANTS: gc_kind_dev       TYPE string VALUE 'DEV',
               gc_kind_toc       TYPE string VALUE 'TOC',
               gc_sync_ok        TYPE string VALUE 'OK',
               gc_sync_error     TYPE string VALUE 'ERROR',
               gc_sync_detached  TYPE string VALUE 'DETACHED',
               gc_sync_unknown   TYPE string VALUE 'UNKNOWN',
               gc_retrofit_na    TYPE string VALUE 'NA',
               gc_retrofit_pend  TYPE string VALUE 'PENDING',
               gc_retrofit_done  TYPE string VALUE 'DONE'.

    CLASS-METHODS link
      IMPORTING iv_cd_id   TYPE zcrw_cd-cd_id
                iv_trkorr  TYPE e070-trkorr
                iv_tr_kind TYPE string
                iv_task_id TYPE zcrw_tr-task_id OPTIONAL
      RAISING   zcx_crw_error.

    CLASS-METHODS unlink
      IMPORTING iv_trkorr TYPE e070-trkorr
      RAISING   zcx_crw_error.

    CLASS-METHODS mark_detached
      IMPORTING iv_trkorr TYPE e070-trkorr
                iv_reason  TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS sync
      IMPORTING iv_trkorr       TYPE e070-trkorr OPTIONAL
      RETURNING VALUE(rv_synced) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_cd_id     TYPE zcrw_tr-cd_id OPTIONAL
                iv_tr_kind    TYPE zcrw_tr-tr_kind OPTIONAL
                iv_target_sys TYPE zcrw_tr-tarsystem OPTIONAL
                iv_sync_state TYPE zcrw_tr-sync_state OPTIONAL
                iv_query      TYPE string OPTIONAL
      RETURNING VALUE(rt_rows) TYPE tt_transports.

    CLASS-METHODS get
      IMPORTING iv_trkorr     TYPE e070-trkorr
      RETURNING VALUE(rs_row) TYPE zcrw_tr
      RAISING   zcx_crw_error.

    CLASS-METHODS objects
      IMPORTING iv_trkorr              TYPE e070-trkorr
      RETURNING VALUE(rt_objects)      TYPE zcl_crw_api_types=>tt_transport_objects
      RAISING   zcx_crw_error.

    CLASS-METHODS status_text
      IMPORTING iv_status      TYPE string
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS refresh_row
      IMPORTING iv_trkorr TYPE zcrw_tr-trkorr
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_transport_svc IMPLEMENTATION.
  METHOD link.
    DATA lo_cts TYPE REF TO zif_crw_cts_reader.
    DATA ls_header TYPE zif_crw_cts_reader=>ty_header.
    DATA ls_row TYPE zcrw_tr.
    DATA ls_existing TYPE zcrw_tr.
    DATA lv_now TYPE char14.

    IF iv_tr_kind <> gc_kind_dev AND iv_tr_kind <> gc_kind_toc.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'trKind must be DEV or TOC'.
    ENDIF.

    zcl_crw_cd_svc=>get( iv_cd_id ).

    lo_cts = NEW zcl_crw_cts_adapter( ).
    TRY.
        ls_header = lo_cts->get_header( iv_trkorr ).
      CATCH zcx_crw_error INTO DATA(lx_cts).
        IF lx_cts->mv_code = 'TR_NOT_FOUND'.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'TR_NOT_FOUND'
                      iv_text = |Transport { iv_trkorr } not found|.
        ENDIF.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'CTS_READ_ERROR'
                    iv_text = |Transport { iv_trkorr } could not be read|.
    ENDTRY.

*   One transport can be linked to one change document only.
    SELECT SINGLE * FROM zcrw_tr WHERE trkorr = @iv_trkorr INTO @ls_existing.
    IF sy-subrc = 0 AND ls_existing-cd_id IS NOT INITIAL AND ls_existing-cd_id <> iv_cd_id.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'DUPLICATE_LINK'
                  iv_text = |Transport { iv_trkorr } is already linked to change document { ls_existing-cd_id }|.
    ENDIF.

    lv_now = zcl_crw_util=>now( ).

    ls_row-trkorr         = iv_trkorr.
    ls_row-cd_id          = iv_cd_id.
    ls_row-task_id        = iv_task_id.
    ls_row-tr_kind        = iv_tr_kind.
    ls_row-tarsystem      = ls_header-tarsystem.
    ls_row-tr_status      = ls_header-trstatus.
    ls_row-tr_status_txt  = status_text( CONV string( ls_header-trstatus ) ).
    ls_row-description    = lo_cts->get_description( iv_trkorr ).
    ls_row-retrofit_state = COND #( WHEN iv_tr_kind = gc_kind_toc THEN gc_retrofit_pend ELSE gc_retrofit_na ).
    ls_row-sync_state     = gc_sync_ok.
    ls_row-last_sync_at   = lv_now.
    ls_row-linked_at      = lv_now.
    ls_row-linked_by      = sy-uname.

    IF ls_header-trstatus = zif_crw_cts_reader=>gc_state_released.
      ls_row-released_at = lv_now.
    ENDIF.

    IF ls_existing-trkorr IS NOT INITIAL.
      ls_row-imported_at         = ls_existing-imported_at.
      ls_row-import_scheduled_at = ls_existing-import_scheduled_at.
      ls_row-sync_state          = ls_existing-sync_state.
      UPDATE zcrw_tr FROM ls_row.
    ELSE.
      INSERT zcrw_tr FROM ls_row.
    ENDIF.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TR_LINK_UPDATE' iv_text = 'Could not store the transport link'.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'TR'
                            iv_object_id   = CONV string( iv_trkorr )
                            iv_action      = 'LINK_TR'
                            iv_field       = 'CD_ID'
                            iv_old_value   = CONV string( ls_existing-cd_id )
                            iv_new_value   = CONV string( iv_cd_id ) ).
      CATCH zcx_crw_error.
    ENDTRY.

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD unlink.
    DATA ls_row TYPE zcrw_tr.

    ls_row = get( iv_trkorr ).

    IF ls_row-tr_status = zif_crw_cts_reader=>gc_state_released OR ls_row-imported_at IS NOT INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'GUARD_FAILED'
                  iv_text = 'A released transport cannot be unlinked; mark it as detached instead'.
    ENDIF.

    UPDATE zcrw_tr
      SET cd_id      = '',
          task_id    = '',
          sync_state = @gc_sync_unknown
      WHERE trkorr = @iv_trkorr.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TR_UNLINK_UPDATE' iv_text = 'Could not unlink the transport'.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'TR'
                            iv_object_id   = CONV string( iv_trkorr )
                            iv_action      = 'UNLINK_TR'
                            iv_field       = 'CD_ID'
                            iv_old_value   = CONV string( ls_row-cd_id )
                            iv_new_value   = '' ).
      CATCH zcx_crw_error.
    ENDTRY.

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD mark_detached.
    DATA ls_row TYPE zcrw_tr.
    DATA lv_now TYPE char14.

    ls_row = get( iv_trkorr ).
    lv_now = zcl_crw_util=>now( ).

    UPDATE zcrw_tr
      SET sync_state   = @gc_sync_detached,
          last_sync_at = @lv_now
      WHERE trkorr = @iv_trkorr.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TR_DETACH_UPDATE' iv_text = 'Could not mark the transport as detached'.
    ENDIF.

    TRY.
        zcl_crw_audit=>log( iv_object_type = 'TR'
                            iv_object_id   = CONV string( iv_trkorr )
                            iv_action      = 'MARK_DETACHED'
                            iv_comment     = iv_reason ).
      CATCH zcx_crw_error.
    ENDTRY.

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD sync.
    DATA lt_rows TYPE tt_transports.
    DATA lv_failed TYPE i.
    DATA lv_error TYPE string.

    IF iv_trkorr IS NOT INITIAL.
      APPEND get( iv_trkorr ) TO lt_rows.
    ELSE.
      SELECT * FROM zcrw_tr WHERE cd_id <> '' INTO TABLE @lt_rows.
    ENDIF.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      TRY.
          refresh_row( <ls_row>-trkorr ).
          rv_synced = rv_synced + 1.
        CATCH zcx_crw_error INTO DATA(lx_sync).
          lv_failed = lv_failed + 1.
          lv_error = lx_sync->mv_text.
          DATA(lv_error_at) = zcl_crw_util=>now( ).
          UPDATE zcrw_tr
            SET sync_state   = @gc_sync_error,
                last_sync_at = @lv_error_at
            WHERE trkorr = @<ls_row>-trkorr.
        ENDTRY.
    ENDLOOP.

    COMMIT WORK AND WAIT.

    IF iv_trkorr IS NOT INITIAL AND lv_failed > 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'CTS_READ_ERROR'
                  iv_text = COND #( WHEN lv_error IS INITIAL THEN 'Transport status could not be read' ELSE lv_error ).
    ENDIF.
  ENDMETHOD.

  METHOD list.
    DATA lv_query TYPE string.

    SELECT * FROM zcrw_tr INTO TABLE @rt_rows ORDER BY linked_at DESCENDING, trkorr ASCENDING.

    IF iv_cd_id IS NOT INITIAL.
      DELETE rt_rows WHERE cd_id <> iv_cd_id.
    ENDIF.
    IF iv_tr_kind IS NOT INITIAL.
      DELETE rt_rows WHERE tr_kind <> iv_tr_kind.
    ENDIF.
    IF iv_target_sys IS NOT INITIAL.
      DELETE rt_rows WHERE tarsystem <> iv_target_sys.
    ENDIF.
    IF iv_sync_state IS NOT INITIAL.
      DELETE rt_rows WHERE sync_state <> iv_sync_state.
    ENDIF.
    IF iv_query IS NOT INITIAL.
      lv_query = to_upper( iv_query ).
      LOOP AT rt_rows INTO DATA(ls_row).
        IF to_upper( ls_row-trkorr ) NS lv_query AND to_upper( ls_row-description ) NS lv_query.
          DELETE rt_rows.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE * FROM zcrw_tr WHERE trkorr = @iv_trkorr INTO @rs_row.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TR_NOT_FOUND' iv_text = |Transport { iv_trkorr } is not linked|.
    ENDIF.
  ENDMETHOD.

  METHOD objects.
    DATA lo_cts TYPE REF TO zif_crw_cts_reader.

    lo_cts = NEW zcl_crw_cts_adapter( ).
    DATA(lt_cts_objects) = lo_cts->get_objects( iv_trkorr ).

    LOOP AT lt_cts_objects ASSIGNING FIELD-SYMBOL(<ls_obj>).
      APPEND VALUE #( pgmid         = <ls_obj>-pgmid
                      object        = <ls_obj>-object
                      obj_name      = <ls_obj>-obj_name
                      obj_type      = <ls_obj>-object
                      obj_name_text = <ls_obj>-obj_name ) TO rt_objects.
    ENDLOOP.
  ENDMETHOD.

  METHOD status_text.
    CASE iv_status.
      WHEN 'D'.
        rv_text = '可修改'.
      WHEN 'R'.
        rv_text = '已释放'.
      WHEN 'I'.
        rv_text = '已导入'.
      WHEN OTHERS.
        rv_text = '未知'.
    ENDCASE.
  ENDMETHOD.

  METHOD refresh_row.
    DATA lo_cts TYPE REF TO zif_crw_cts_reader.
    DATA ls_header TYPE zif_crw_cts_reader=>ty_header.
    DATA ls_row TYPE zcrw_tr.
    DATA lv_now TYPE char14.
    DATA lv_import_state TYPE string.
    DATA lv_released TYPE char14.
    DATA lv_imported TYPE char14.
    DATA lv_status_txt TYPE char30.
    DATA lv_e070_trkorr TYPE e070-trkorr.

    lv_e070_trkorr = iv_trkorr.
    lo_cts = NEW zcl_crw_cts_adapter( ).
    ls_header = lo_cts->get_header( lv_e070_trkorr ).
    lv_now = zcl_crw_util=>now( ).
    lv_import_state = lo_cts->get_import_state( lv_e070_trkorr ).
    lv_status_txt = status_text( CONV string( ls_header-trstatus ) ).

    SELECT SINGLE * FROM zcrw_tr WHERE trkorr = @iv_trkorr INTO @ls_row.
    lv_released = ls_row-released_at.
    lv_imported = ls_row-imported_at.

    IF ls_header-trstatus = zif_crw_cts_reader=>gc_state_released AND lv_released IS INITIAL.
      lv_released = lv_now.
    ENDIF.
    IF lv_import_state = zif_crw_cts_reader=>gc_state_imported AND lv_imported IS INITIAL.
      lv_imported = lv_now.
    ENDIF.

    UPDATE zcrw_tr
      SET tr_status     = @ls_header-trstatus,
          tr_status_txt = @lv_status_txt,
          tarsystem     = @ls_header-tarsystem,
          last_sync_at  = @lv_now,
          sync_state    = @gc_sync_ok,
          released_at   = @lv_released,
          imported_at   = @lv_imported
      WHERE trkorr = @iv_trkorr.
  ENDMETHOD.
ENDCLASS.
