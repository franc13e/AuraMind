// lib/config.dart
//
// Backend base URL. Release builds call the API on the same origin
// (Vercel serves it under /api), debug builds talk to a local uvicorn server.
// Override with --dart-define=API_BASE=https://your-backend/api/v1/auramind

import 'package:flutter/foundation.dart';

const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: kReleaseMode
      ? '/api/v1/auramind'
      : 'http://localhost:8001/api/v1/auramind',
);
