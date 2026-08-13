/**
 * SIS login fill-and-submit script.
 * Call this on the login page with credentials; it fills the form and clicks submit.
 * @param {string} studentNumber
 * @param {string} birthMonth
 * @param {string} birthDay
 * @param {string} birthYear
 * @param {string} password
 */
(function(studentNumber, birthMonth, birthDay, birthYear, password) {
  function setField(id, value) {
    var el = document.getElementById(id);
    if (!el) return;
    el.value = value;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  setField('studno', studentNumber);
  setField('SelectMonth', birthMonth);
  setField('SelectDay', birthDay);
  setField('SelectYear', birthYear);
  setField('password', password);

  var submit = document.querySelector('input[type=submit]');
  if (submit) submit.click();
})(%ARGS%);
