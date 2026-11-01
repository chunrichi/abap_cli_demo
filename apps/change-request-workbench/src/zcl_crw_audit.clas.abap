CLASS zcl_crw_audit DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_history TYPE STANDARD TABLE OF zcrw_hist WITH EMPTY KEY.

    CLASS-METHODS log
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_action      TYPE string
                iv_field       TYPE string DEFAULT ''
                iv_old_value   TYPE string DEFAULT ''
                iv_new_value   TYPE string DEFAULT ''
                iv_comment     TYPE string DEFAULT ''
                iv_source      TYPE string DEFAULT 'API'
      RAISING   zcx_crw_error.

    CLASS-METHODS list
      IMPORTING iv_object_type   TYPE string
                iv_object_id     TYPE string
                iv_offset        TYPE i DEFAULT 0
                iv_size          TYPE i DEFAULT 50
      RETURNING VALUE(rt_history) TYPE tt_history.

    CLASS-METHODS count
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_total) TYPE i.

    CLASS-METHODS recent
      IMPORTING iv_size          TYPE i DEFAULT 20
      RETURNING VALUE(rt_history) TYPE tt_history.

  PRIVATE SECTION.
    CLASS-METHODS truncate
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS zcl_crw_audit IMPLEMENTATION.
  METHOD log.
    DATA ls_hist TYPE zcrw_hist.

    ls_hist-hist_id = zcl_crw_util=>uuid( ).
    IF ls_hist-hist_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'AUDIT_UUID'
          iv_text = 'Could not create an audit id'.
    ENDIF.

    ls_hist-object_type = iv_object_type.
    ls_hist-object_id   = truncate( iv_object_id ).
    ls_hist-action      = truncate( iv_action ).
    ls_hist-field       = truncate( iv_field ).
    ls_hist-old_value   = truncate( iv_old_value ).
    ls_hist-new_value   = truncate( iv_new_value ).
    ls_hist-comment_txt = truncate( iv_comment ).
    ls_hist-changed_by  = sy-uname.
    ls_hist-changed_at  = zcl_crw_util=>now( ).
    ls_hist-source      = iv_source.

    INSERT zcrw_hist FROM ls_hist.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'AUDIT_INSERT'
          iv_text = 'Could not write the audit row'.
    ENDIF.
  ENDMETHOD.

  METHOD list.
    DATA: lt_rows TYPE tt_history,
          lv_from TYPE i,
          lv_to   TYPE i.

    SELECT *
      FROM zcrw_hist
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
      ORDER BY changed_at DESCENDING, hist_id DESCENDING
      INTO TABLE @lt_rows.

    lv_from = iv_offset + 1.
    lv_to   = iv_offset + iv_size.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND <ls_row> TO rt_history.
    ENDLOOP.
  ENDMETHOD.

  METHOD count.
    SELECT COUNT(*)
      FROM zcrw_hist
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
      INTO @rv_total.
  ENDMETHOD.

  METHOD recent.
    SELECT *
      FROM zcrw_hist
      INTO TABLE @rt_history
      UP TO @iv_size ROWS
      ORDER BY changed_at DESCENDING, hist_id DESCENDING.
  ENDMETHOD.

  METHOD truncate.
    rv_text = iv_text.
    IF strlen( rv_text ) > 255.
      rv_text = substring( val = rv_text len = 255 ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
