CLASS zcl_dma_01_stats_cleanup DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS gc_node_name TYPE icfname VALUE 'ZDMA_01_STATS'.
ENDCLASS.


CLASS zcl_dma_01_stats_cleanup IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    " Transient classrun: removes the demo ICF node because `abap delete`
    " has no SICF delete endpoint.
    DATA: lv_guid   TYPE icfparguid,
          lv_parent TYPE icfparguid,
          lv_name   TYPE icfname,
          lv_msg    TYPE string.

    SELECT SINGLE icfnodguid, icfparguid, icf_name
      FROM icfservice
      INTO (@lv_guid, @lv_parent, @lv_name)
      WHERE icf_name = @gc_node_name.
    IF sy-subrc <> 0.
      out->write( |DMA_CLEANUP_SKIP { gc_node_name }| ).
      RETURN.
    ENDIF.

    CALL METHOD cl_icf_tree=>if_icf_tree~delete_node
      EXPORTING
        icfparguid = lv_parent
      CHANGING
        icf_name   = lv_name
      EXCEPTIONS
        no_virtual_host_delete      = 1
        special_service_error       = 2
        enqueue_error               = 3
        node_not_existing           = 4
        node_has_childs             = 5
        node_is_aliased             = 6
        node_not_in_original_system = 7
        transport_error             = 8
        tadir_error                 = 9
        db_error                    = 10
        no_authority                = 11
        OTHERS                      = 12.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_msg.
      out->write( |DMA_CLEANUP_FAIL subrc={ sy-subrc } node={ lv_guid } parent={ lv_parent } { lv_msg }| ).
    ELSE.
      out->write( |DMA_CLEANUP_OK { gc_node_name }| ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
