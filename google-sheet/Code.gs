/**
 * Ghost Town: invite requests -> Google Sheet
 * Paste this into Extensions > Apps Script of your Google Sheet, then deploy it as a Web app.
 * Every request from the invite page lands as one row on the "Requests" tab.
 */
const SHEET_NAME = 'Requests';
const HEADERS = ['Received', 'Name', 'Phone', 'Instagram', 'Who sent them', 'Status', 'Notes'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const d = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    if (!d.name || !d.phone) return reply({ ok: false, error: 'missing fields' });

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(SHEET_NAME);
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow(HEADERS);
      sheet.setFrozenRows(1);
      sheet.getRange('F2:F').setDataValidation(
        SpreadsheetApp.newDataValidation().requireValueInList(['Pending', 'Approved', 'Paid', 'Declined'], true).build()
      );
    }
    // Text only, capped, and never read as a formula.
    const clean = (v) => String(v || '').slice(0, 200).replace(/^[=+\-@]/, "'$&");
    sheet.appendRow([
      new Date(),
      clean(d.name),
      clean(d.phone),
      clean('@' + String(d.instagram || '').replace(/^@/, '')),
      clean(d.referrer),
      'Pending',
      ''
    ]);
    return reply({ ok: true });
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// Lets you open the web app URL in a browser to check it's live.
function doGet() {
  return reply({ ok: true, message: 'Ghost Town request endpoint is live.' });
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
