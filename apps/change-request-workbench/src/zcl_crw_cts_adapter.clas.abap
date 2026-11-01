CLASS zcl_crw_cts_adapter DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_crw_cts_reader.
ENDCLASS.

CLASS zcl_crw_cts_adapter IMPLEMENTATION.
  METHOD zif_crw_cts_reader~get_header.
    SELECT SINGLE trkorr, trfunction, trstatus, tarsystem, as4user, as4date, as4time
      FROM e070
      WHERE trkorr = @iv_trkorr
      INTO CORRESPONDING FIELDS OF @rs_header.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'TR_NOT_FOUND'
                  iv_text = |Transport request { iv_trkorr } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_crw_cts_reader~get_description.
    SELECT SINGLE as4text
      FROM e07t
      WHERE trkorr = @iv_trkorr
        AND langu  = @sy-langu
      INTO @DATA(lv_text).

    IF sy-subrc <> 0.
      SELECT SINGLE as4text
        FROM e07t
        WHERE trkorr = @iv_trkorr
          AND langu  = 'E'
        INTO @lv_text.
    ENDIF.

    rv_text = lv_text.
  ENDMETHOD.

  METHOD zif_crw_cts_reader~get_objects.
    DATA lt_rows TYPE STANDARD TABLE OF e071 WITH EMPTY KEY.

    SELECT *
      FROM e071
      WHERE trkorr = @iv_trkorr
      INTO TABLE @lt_rows.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND VALUE #( pgmid    = <ls_row>-pgmid
                      object   = <ls_row>-object
                      obj_name = <ls_row>-obj_name ) TO rt_objects.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_crw_cts_reader~get_import_state.
    DATA lv_imported TYPE tmsbuffer-impflg.
    DATA lv_status TYPE e070-trstatus.

    SELECT SINGLE impflg
      FROM tmsbuffer
      WHERE trkorr = @iv_trkorr
      INTO @lv_imported.

    IF sy-subrc = 0 AND lv_imported = 'X'.
      rv_state = zif_crw_cts_reader~gc_state_imported.
      RETURN.
    ENDIF.

    SELECT SINGLE trstatus
      FROM e070
      WHERE trkorr = @iv_trkorr
      INTO @lv_status.

    IF lv_status = zif_crw_cts_reader~gc_state_released.
      rv_state = zif_crw_cts_reader~gc_state_released.
    ELSEIF lv_status = zif_crw_cts_reader~gc_state_modifiable.
      rv_state = zif_crw_cts_reader~gc_state_modifiable.
    ELSE.
      rv_state = zif_crw_cts_reader~gc_state_unknown.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
