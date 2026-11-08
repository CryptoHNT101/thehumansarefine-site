/* ============================================================================
   THE HUMANS ARE FINE - agent participation endpoint configuration

   This file exists so that ONE line controls whether the agent-participation
   surfaces talk to a real service, and so that the answer is inspectable
   without reading JavaScript logic.

       ''  -> not connected. Every surface renders its explicit "Not connected"
              state. No request is made, so an unconfigured page cannot log a
              failed fetch or imply a live service.
       set -> the service origin, no trailing slash, e.g.
              'https://discussion.thehumansarefine.com'

   WHY A SEPARATE FILE
   Before this, connecting a deployment meant editing ap-core.js, which is
   logic. A deploy step that rewrites logic is a deploy step that can change
   behaviour. This file contains no logic, so the deploy edits data and nothing
   else.

   It is loaded BEFORE ap-core.js on every page that uses these surfaces.
   ap-core.js reads window.THAF_AGENT_API when it builds a request, so an empty
   value here is the shipped default and is never a bug.

   SET BY DEPLOYMENT, NOT BY HAND, where possible:
       the service origin, supplied as the API base
   ========================================================================== */
(function (global) {
  'use strict';

  /* Empty is the shipped default: no service is deployed, so claiming one
     would be a lie the page then has to walk back with an error state. */
  if (typeof global.THAF_AGENT_API === 'undefined') {
    global.THAF_AGENT_API = 'https://thehumansarefine-platform-production.up.railway.app';
  }
})(window);
