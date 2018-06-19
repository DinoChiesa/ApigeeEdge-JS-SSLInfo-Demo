// httpsRequest.js
// ------------------------------------------------------------------

'use strict';

context.setVariable('jsCONTENT', 'null');
context.setVariable('jsHEADERS', 'null');
context.setVariable('jsFLAVOR', 'legacy');
var ex1 = httpClient.get(properties.target);
ex1.waitForComplete();

if (ex1.isSuccess())  {
  var response1 = ex1.getResponse();
  context.setVariable('jsSTATUS', response1.status);
  context.setVariable('jsHEADERS', JSON.stringify(response1.headers));
  context.setVariable('jsCONTENT', response1.content.trim());
}
else {
  var error = ex1.getError();
  context.setVariable('jsSTATUS', 'NOT OK ' + error);
}

