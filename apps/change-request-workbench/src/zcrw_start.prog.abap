*&---------------------------------------------------------------------*
*& Report ZCRW_START
*&---------------------------------------------------------------------*
*& Launcher for the change request workbench ICF node.
*& The transaction ZCRW starts this report; the report shows the system
*& URL of the SPA and can open it in the default browser.
*&---------------------------------------------------------------------*
REPORT zcrw_start.

CONSTANTS gc_service_path TYPE string VALUE '/sap/bc/zcrw/'.

DATA gv_url TYPE string.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
PARAMETERS p_url TYPE string LOWER CASE DEFAULT '/sap/bc/zcrw/'.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  TRY.
      DATA(lv_system_url) = cl_abap_context_info=>get_system_url( ).
      IF lv_system_url IS NOT INITIAL.
        gv_url = lv_system_url && gc_service_path.
        p_url = gv_url.
      ELSE.
        gv_url = p_url.
      ENDIF.
    CATCH cx_abap_context_info_error.
      gv_url = p_url.
  ENDTRY.

START-OF-SELECTION.
  IF gv_url IS INITIAL.
    WRITE: / '无法解析系统地址，请手工打开 ICF 节点 /sap/bc/zcrw/。'.
    RETURN.
  ENDIF.

  WRITE: / '变更请求工作台地址：', gv_url.
  WRITE: / '请复制上面的地址到浏览器打开（事务码 ZCRW 仅作为入口）。'.
