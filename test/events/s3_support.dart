// Shared helpers for the events S3 tests: the extra routes the pages
// navigate to, and the member user.
import 'package:fitflexmobile/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const member = {'id': 'u1', 'userType': 'member'};

/// Stand-in pages for every route an S3 screen can go to.
final s3Routes = <RouteBase>[
  GoRoute(
    path: AppRoutes.memberActivity,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-ACTIVITY')),
  ),
  GoRoute(
    path: AppRoutes.memberEvents,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-EVENTS')),
  ),
  GoRoute(
    path: AppRoutes.memberEventOrders,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-ORDERS')),
  ),
  GoRoute(
    path: AppRoutes.memberEventOrderDetail,
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-ORDER-${s.pathParameters['orderId']}')),
  ),
  GoRoute(
    path: AppRoutes.memberEventRegistration,
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-REG-${s.pathParameters['registrationId']}')),
  ),
  GoRoute(
    path: AppRoutes.memberEventClaim,
    builder: (_, s) => Scaffold(
      body: Text('ROUTE-CLAIM-${s.pathParameters['registrationId']}'),
    ),
  ),
  GoRoute(
    path: AppRoutes.memberEventTeam,
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-TEAM-${s.pathParameters['teamId']}')),
  ),
  GoRoute(
    path: AppRoutes.memberEventDetail,
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-EVENT-${s.pathParameters['eventId']}')),
    routes: [
      GoRoute(
        path: 'register',
        builder: (_, s) => Scaffold(
          body: Text(
            'ROUTE-REGISTER-${s.pathParameters['eventId']}'
            '-${s.uri.queryParameters['ticket'] ?? ''}',
          ),
        ),
      ),
    ],
  ),
];
