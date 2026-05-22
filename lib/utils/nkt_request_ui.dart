import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';

Color nktRequestStatusColor(String? status) {
  switch (status) {
    case 'new':
    case 'cancelled':
      return AppColors.muted;
    case 'onModeration':
    case 'accepted':
    case 'acceptedGz':
      return AppColors.primary;
    case 'underRevision':
    case 'underRevisionGz':
    case 'rejected':
    case 'rejectedGz':
      return AppColors.danger;
    case 'readyToPublish':
      return AppColors.primary;
    case 'completed':
    case 'publishingGz':
      return AppColors.accent;
    default:
      return AppColors.muted;
  }
}

bool nktCanSubmitModeration(Product product) {
  final s = product.nktRequestStatus;
  if (s == null) return product.hasNktRequest;
  return s == 'new' ||
      s == 'underRevision' ||
      s == 'underRevisionGz' ||
      s == 'cancelled';
}

bool nktCanPublishRequest(Product product) =>
    product.nktRequestStatus == 'readyToPublish';

bool nktCanCancelRequest(Product product) =>
    product.nktRequestStatus == 'onModeration';

bool nktCanEditRequest(Product product) {
  final s = product.nktRequestStatus;
  return s == 'rejected' ||
      s == 'underRevision' ||
      s == 'underRevisionGz' ||
      s == 'new' ||
      s == 'cancelled';
}

bool nktCanCreateRequest(Product product) =>
    !product.isLinkedToNkt && !product.hasNktRequest;
