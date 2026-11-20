import { encodeBase64Url } from "jsr:@std/encoding@1/base64url";
import { encodeHex } from "jsr:@std/encoding@1/hex";

export function newToken() {
  return encodeBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function hashToken(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return encodeHex(digest);
}
