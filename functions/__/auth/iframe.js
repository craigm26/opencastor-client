/**
 * Cloudflare Pages Function — Firebase Auth iFrame Proxy
 *
 * Firebase uses /__/auth/iframe to sync auth state between tabs
 * via a hidden iFrame. Must be served on the same authDomain.
 */
export async function onRequest(context) {
  const url = new URL(context.request.url);
  const proxyUrl = new URL(
    `/__/auth/iframe${url.search}`,
    'https://opencastor.firebaseapp.com'
  );

  const proxied = await fetch(proxyUrl.toString(), {
    method: context.request.method,
    headers: Object.fromEntries(context.request.headers),
    redirect: 'manual',
  });

  return new Response(proxied.body, {
    status: proxied.status,
    statusText: proxied.statusText,
    headers: new Headers(proxied.headers),
  });
}
