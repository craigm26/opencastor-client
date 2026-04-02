/**
 * Cloudflare Pages Function — Firebase Auth Domain Proxy
 *
 * Firebase requires the authDomain to match the app's origin so that
 * Safari's ITP (Intelligent Tracking Prevention) doesn't block
 * cross-origin IndexedDB access during signInWithRedirect flows.
 *
 * By setting authDomain: "app.opencastor.com" in firebase_options.dart,
 * Firebase redirects to app.opencastor.com/__/auth/handler for the
 * OAuth callback. This function proxies that request to Firebase's
 * actual auth handler at opencastor.firebaseapp.com/__/auth/handler,
 * which completes the OAuth flow.
 *
 * Result: auth state is stored in app.opencastor.com's IndexedDB
 * (same-origin), which Safari ITP allows. getRedirectResult() succeeds.
 *
 * See: https://firebase.google.com/docs/auth/web/redirect-best-practices
 */
export async function onRequest(context) {
  const url = new URL(context.request.url);
  const proxyUrl = new URL(
    `/__/auth/handler${url.search}`,
    'https://opencastor.firebaseapp.com'
  );

  const proxied = await fetch(proxyUrl.toString(), {
    method: context.request.method,
    headers: {
      ...Object.fromEntries(context.request.headers),
      // Forward the original host so Firebase knows the auth domain
      'X-Forwarded-Host': url.host,
    },
    body: ['GET', 'HEAD'].includes(context.request.method)
      ? undefined
      : context.request.body,
    redirect: 'manual',
  });

  // Forward the response body and headers as-is.
  // Do NOT follow redirects — return them so the browser handles them
  // (Firebase auth handler may redirect back to the app).
  const responseHeaders = new Headers(proxied.headers);

  return new Response(proxied.body, {
    status: proxied.status,
    statusText: proxied.statusText,
    headers: responseHeaders,
  });
}
