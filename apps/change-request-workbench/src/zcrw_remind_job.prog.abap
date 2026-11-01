*&---------------------------------------------------------------------*
*& Report ZCRW_REMIND_JOB
*&---------------------------------------------------------------------*
*& Reminder scan for the change request workbench.
*& Schedule this report as a daily background job (SM36, job ZCRW_REMIND).
*& It creates in-app notifications for pending approvals, overdue tasks
*& and overdue import schedules. No mail is sent (SMTP not configured).
*&---------------------------------------------------------------------*
REPORT zcrw_remind_job.

START-OF-SELECTION.
  PERFORM run_reminder_scan.

*&---------------------------------------------------------------------*
*& Form run_reminder_scan
*&---------------------------------------------------------------------*
*& Run the notification scan and print the created counters.
*&---------------------------------------------------------------------*
FORM run_reminder_scan.
  DATA ls_result TYPE zcl_crw_notify=>ty_scan_result.

  TRY.
      ls_result = zcl_crw_notify=>run_scan( ).
      COMMIT WORK AND WAIT.
      WRITE: / |ZCRW_REMIND_JOB_OK approvals={ ls_result-approval_created }| &&
               | tasks={ ls_result-task_created } schedules={ ls_result-schedule_created }| &&
               | total={ ls_result-total_created }|.
    CATCH zcx_crw_error INTO DATA(lx_error).
      ROLLBACK WORK.
      WRITE: / |ZCRW_REMIND_JOB_FAIL { lx_error->mv_code } { lx_error->mv_text }|.
  ENDTRY.
ENDFORM.
