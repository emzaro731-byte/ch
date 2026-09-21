# Veylola Trade Bybit backend
Deploy the bybit Edge Function and set Supabase secrets:
- BYBIT_ENCRYPTION_KEY: a long random value used to encrypt stored Bybit API secrets.
- BYBIT_BASE_URL: optional, defaults to https://api.bybit.com
The Flutter app never receives or stores the Bybit API secret after connection. The Edge Function signs authenticated Bybit requests server-side.