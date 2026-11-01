CLASS zcl_crw_audit DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
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
    ls_hist-object_id   = iv_object_id.
    ls_hist-action      = iv_action.
    ls_hist-field       = iv_field.
    ls_hist-old_value   = iv_old_value.
    ls_hist-new_value   = iv_new_value.
    ls_hist-comment_txt = iv_comment.
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
ENDCLASS.
