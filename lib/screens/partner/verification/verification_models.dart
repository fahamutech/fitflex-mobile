// Partner verification (KYC / KYB) — typed views of GET /me/kyc and the
// per-partner requirements the forms need. The server's checklist is the
// source of truth for what is missing; these specs only decide which fields
// and documents each form shows, mirroring src/shared/partner-kyc-requirements.mjs.

enum KycStatus {
  none,
  draft,
  submitted,
  inReview,
  infoRequested,
  approved,
  rejected,
  suspended;

  static KycStatus parse(String? wire) => switch (wire) {
    'draft' => draft,
    'submitted' => submitted,
    'in_review' => inReview,
    'info_requested' => infoRequested,
    'approved' => approved,
    'rejected' => rejected,
    'suspended' => suspended,
    _ => none,
  };

  /// The partner can still change their details.
  bool get editable => this == none || this == draft || this == infoRequested;
}

class KycAddress {
  const KycAddress({
    this.line1,
    this.line2,
    this.city,
    this.region,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? city;
  final String? region;
  final String? country;

  factory KycAddress.fromJson(Map<String, dynamic>? j) => KycAddress(
    line1: j?['line1'] as String?,
    line2: j?['line2'] as String?,
    city: j?['city'] as String?,
    region: j?['region'] as String?,
    country: j?['country'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'line1': line1 ?? '',
    'line2': line2 ?? '',
    'city': city ?? '',
    'region': region ?? '',
    'country': country ?? '',
  };

  bool get complete =>
      (line1 ?? '').trim().isNotEmpty && (city ?? '').trim().isNotEmpty;

  String get oneLine => [
    line1,
    line2,
    city,
    region,
    country,
  ].where((v) => v != null && v.trim().isNotEmpty).join(', ');
}

class KycCaseInfo {
  const KycCaseInfo({
    required this.id,
    required this.status,
    this.round = 1,
    this.reasonCode,
    this.reasonNote,
    this.legalName,
    this.tradingName,
    this.entityType,
    this.registrationNumber,
    this.tin,
    this.registeredAddress = const KycAddress(),
    this.submittedAt,
    this.reverifyAt,
  });

  final String id;
  final KycStatus status;
  final int round;
  final String? reasonCode;
  final String? reasonNote;
  final String? legalName;
  final String? tradingName;
  final String? entityType;
  final String? registrationNumber;
  final String? tin;
  final KycAddress registeredAddress;
  final DateTime? submittedAt;
  final DateTime? reverifyAt;

  factory KycCaseInfo.fromJson(Map<String, dynamic> j) => KycCaseInfo(
    id: j['id'] as String,
    status: KycStatus.parse(j['status'] as String?),
    round: (j['round'] as num?)?.toInt() ?? 1,
    reasonCode: j['reasonCode'] as String?,
    reasonNote: j['reasonNote'] as String?,
    legalName: j['legalName'] as String?,
    tradingName: j['tradingName'] as String?,
    entityType: j['entityType'] as String?,
    registrationNumber: j['registrationNumber'] as String?,
    tin: j['tin'] as String?,
    registeredAddress: KycAddress.fromJson(
      (j['registeredAddress'] as Map?)?.cast(),
    ),
    submittedAt: DateTime.tryParse('${j['submittedAt']}'),
    reverifyAt: DateTime.tryParse('${j['reverifyAt']}'),
  );
}

class KycPerson {
  const KycPerson({
    required this.role,
    this.fullName,
    this.dateOfBirth,
    this.nationality,
    this.idType,
    this.idNumber,
    this.phone,
    this.email,
    this.address = const KycAddress(),
    this.position,
    this.relationship,
    this.authority,
  });

  final String role;
  final String? fullName;
  final String? dateOfBirth;
  final String? nationality;
  final String? idType;
  final String? idNumber;
  final String? phone;
  final String? email;
  final KycAddress address;
  final String? position;
  final String? relationship;
  final String? authority;

  factory KycPerson.fromJson(Map<String, dynamic> j) => KycPerson(
    role: j['role'] as String,
    fullName: j['fullName'] as String?,
    dateOfBirth: j['dateOfBirth'] as String?,
    nationality: j['nationality'] as String?,
    idType: j['idType'] as String?,
    idNumber: j['idNumber'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    address: KycAddress.fromJson((j['address'] as Map?)?.cast()),
    position: j['position'] as String?,
    relationship: j['relationship'] as String?,
    authority: j['authority'] as String?,
  );
}

class KycDocument {
  const KycDocument({
    required this.id,
    required this.requirementKey,
    required this.docType,
    required this.status,
    required this.hasFile,
    this.fileName,
    this.documentNumber,
    this.issuer,
    this.issuedOn,
    this.expiresOn,
    this.reviewNote,
    this.createdAt,
  });

  final String id;
  final String requirementKey;
  final String docType;
  final String status; // pending | accepted | rejected | expired | superseded
  final bool hasFile;
  final String? fileName;
  final String? documentNumber;
  final String? issuer;
  final String? issuedOn;
  final String? expiresOn;
  final String? reviewNote;
  final DateTime? createdAt;

  factory KycDocument.fromJson(Map<String, dynamic> j) => KycDocument(
    id: j['id'] as String,
    requirementKey: j['requirementKey'] as String,
    docType: j['docType'] as String? ?? '',
    status: j['status'] as String? ?? 'pending',
    hasFile: j['hasFile'] == true,
    fileName: j['fileName'] as String?,
    documentNumber: j['documentNumber'] as String?,
    issuer: j['issuer'] as String?,
    issuedOn: j['issuedOn'] as String?,
    expiresOn: j['expiresOn'] as String?,
    reviewNote: j['reviewNote'] as String?,
    createdAt: DateTime.tryParse('${j['createdAt']}'),
  );
}

class PayoutAccount {
  const PayoutAccount({
    required this.id,
    required this.method,
    required this.provider,
    required this.accountName,
    required this.accountNumber,
    required this.status,
    this.isPrimary = false,
    this.branch,
  });

  final String id;
  final String method; // bank | mobile_money
  final String provider;
  final String accountName;
  final String accountNumber;
  final String status; // pending_verification | verified | rejected | disabled
  final bool isPrimary;
  final String? branch;

  factory PayoutAccount.fromJson(Map<String, dynamic> j) => PayoutAccount(
    id: j['id'] as String,
    method: j['method'] as String? ?? 'bank',
    provider: j['provider'] as String? ?? '',
    accountName: j['accountName'] as String? ?? '',
    accountNumber: j['accountNumber'] as String? ?? '',
    status: j['status'] as String? ?? 'pending_verification',
    isPrimary: j['isPrimary'] == true,
    branch: j['branch'] as String?,
  );
}

class KycItem {
  const KycItem({
    required this.key,
    required this.status,
    this.byReviewer = false,
    this.optional = false,
    this.gymId,
    this.gymName,
    this.requirementKey,
    this.missingFields = const [],
    this.note,
  });

  final String key;
  final String
  status; // complete | submitted | missing | incomplete | file_missing | rejected | expired | failed | mismatch
  final bool byReviewer;

  /// Collected if given, never required (e.g. a vendor's business licence).
  final bool optional;
  final String? gymId;
  final String? gymName;
  final String? requirementKey;
  final List<String> missingFields;
  final String? note;

  factory KycItem.fromJson(Map<String, dynamic> j) => KycItem(
    key: j['key'] as String,
    status: j['status'] as String? ?? 'missing',
    byReviewer: j['by'] == 'reviewer',
    optional: j['optional'] == true,
    gymId: j['gymId'] as String?,
    gymName: j['gymName'] as String?,
    requirementKey: j['requirementKey'] as String?,
    missingFields: ((j['missingFields'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(),
    note: j['note'] as String?,
  );

  String get section => key.split('.').first;
  String get field => key.split('.').last;
  bool get done => status == 'complete' || status == 'submitted';
}

class KycSection {
  const KycSection(this.key, this.items);
  final String key;
  final List<KycItem> items;
}

class KycOverview {
  const KycOverview({
    required this.partnerType,
    this.kycCase,
    this.people = const [],
    this.documents = const [],
    this.accounts = const [],
    this.sections = const [],
    this.missing = const [],
    this.readyToSubmit = false,
    this.complete = false,
  });

  final String partnerType; // gym_owner | trainer | vendor
  final KycCaseInfo? kycCase;
  final List<KycPerson> people;
  final List<KycDocument> documents;
  final List<PayoutAccount> accounts;
  final List<KycSection> sections;
  final List<String> missing;
  final bool readyToSubmit;
  final bool complete;

  factory KycOverview.fromJson(Map<String, dynamic> j) {
    final checklist =
        (j['checklist'] as Map?)?.cast<String, dynamic>() ?? const {};
    return KycOverview(
      partnerType: j['partnerType'] as String? ?? '',
      kycCase: j['case'] is Map
          ? KycCaseInfo.fromJson((j['case'] as Map).cast())
          : null,
      people: ((j['people'] as List?) ?? const [])
          .map((p) => KycPerson.fromJson((p as Map).cast()))
          .toList(),
      documents: ((j['documents'] as List?) ?? const [])
          .map((d) => KycDocument.fromJson((d as Map).cast()))
          .toList(),
      accounts: ((j['settlementAccounts'] as List?) ?? const [])
          .map((a) => PayoutAccount.fromJson((a as Map).cast()))
          .toList(),
      sections: ((checklist['sections'] as List?) ?? const []).map((s) {
        final sec = (s as Map).cast<String, dynamic>();
        return KycSection(
          sec['key'] as String,
          ((sec['items'] as List?) ?? const [])
              .map((i) => KycItem.fromJson((i as Map).cast()))
              .toList(),
        );
      }).toList(),
      missing: ((checklist['missing'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      readyToSubmit: checklist['readyToSubmit'] == true,
      complete: checklist['complete'] == true,
    );
  }

  KycStatus get status => kycCase?.status ?? KycStatus.none;
  bool get editable => status.editable;

  KycPerson? personFor(String role) {
    for (final p in people) {
      if (p.role == role) return p;
    }
    return null;
  }

  /// The document standing for a requirement: the newest one not superseded.
  KycDocument? currentDocument(String requirementKey) {
    final docs =
        documents
            .where(
              (d) =>
                  d.requirementKey == requirementKey &&
                  d.status != 'superseded',
            )
            .toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
    return docs.isEmpty ? null : docs.first;
  }

  int get itemsLeft => missing.length;
}

// ── What each partner type fills in ─────────────────────────────────────────

class DocumentSpec {
  const DocumentSpec(this.types, this.fields);
  final List<String> types; // accepted document types, first is the default
  final List<String> fields; // documentNumber | issuer | issuedOn | expiresOn
}

const documentSpecs = <String, DocumentSpec>{
  'owner_id': DocumentSpec(
    ['national_id', 'passport'],
    ['documentNumber', 'expiresOn'],
  ),
  'trainer_id': DocumentSpec(
    ['national_id', 'passport'],
    ['documentNumber', 'expiresOn'],
  ),
  'representative_id': DocumentSpec(
    ['national_id', 'passport'],
    ['documentNumber', 'expiresOn'],
  ),
  'business_registration': DocumentSpec(
    ['business_registration'],
    ['documentNumber'],
  ),
  'tin_certificate': DocumentSpec(['tin_certificate'], ['documentNumber']),
  'business_licence': DocumentSpec(
    ['business_licence'],
    ['documentNumber', 'issuer', 'expiresOn'],
  ),
  'certification': DocumentSpec(
    ['certification'],
    ['issuer', 'documentNumber', 'issuedOn', 'expiresOn'],
  ),
  'liability_insurance': DocumentSpec(
    ['liability_insurance'],
    ['issuer', 'documentNumber', 'expiresOn'],
  ),
  'representative_authority': DocumentSpec([
    'letter_of_authority',
    'board_resolution',
  ], []),
};

/// The one person each partner type names.
String personRoleFor(String partnerType) =>
    partnerType == 'vendor' ? 'authorised_representative' : 'principal';

/// Identity fields each partner type's form shows, in order.
List<String> personFieldsFor(String partnerType) => switch (partnerType) {
  'gym_owner' => const [
    'fullName',
    'nationality',
    'idType',
    'idNumber',
    'phone',
    'email',
    'address',
    'relationship',
    'position',
  ],
  'trainer' => const [
    'fullName',
    'nationality',
    'idType',
    'idNumber',
    'phone',
    'email',
    'address',
  ],
  _ => const [
    'fullName',
    'nationality',
    'idType',
    'idNumber',
    'position',
    'authority',
    'phone',
    'email',
  ],
};

/// Partners with a business section (trainers are individuals).
bool hasBusinessFor(String partnerType) =>
    partnerType == 'gym_owner' || partnerType == 'vendor';

const entityTypes = ['sole_proprietor', 'partnership', 'company', 'ngo'];
const relationships = [
  'owner',
  'co_owner',
  'director',
  'manager',
  'employee',
  'other',
];
const authorities = ['sole_signatory', 'joint_signatory', 'delegated'];
const mobileMoneyProviders = ['mpesa', 'airtel_money', 'mixx', 'halopesa'];

/// Nationalities offered for identity (ISO codes the API accepts).
const countries = <String, String>{
  'TZ': 'Tanzania',
  'KE': 'Kenya',
  'UG': 'Uganda',
  'RW': 'Rwanda',
  'BI': 'Burundi',
  'CD': 'DR Congo',
  'ZM': 'Zambia',
  'MW': 'Malawi',
  'MZ': 'Mozambique',
  'ZA': 'South Africa',
  'NG': 'Nigeria',
  'GB': 'United Kingdom',
  'US': 'United States',
  'IN': 'India',
};
