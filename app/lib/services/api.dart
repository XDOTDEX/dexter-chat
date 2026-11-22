import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// Thin REST client for the DexterChat server. Mirrors server/README.md.
class ApiClient {
  String baseUrl;
  String? token;

  ApiClient(this.baseUrl);

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _call(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = _u(path, query);
    final req = http.Request(method, uri);
    req.headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    Map<String, dynamic> data = {};
    if (resp.body.isNotEmpty) {
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        data = {'detail': resp.body};
      }
    }
    if (resp.statusCode >= 400) {
      throw ApiException(
          resp.statusCode, (data['detail'] ?? 'request failed').toString());
    }
    return data;
  }

  // ------------------------------------------------------------ auth
  Future<String> walletChallenge(String address) async {
    final r = await _call('POST', '/auth/wallet/challenge',
        body: {'address': address});
    return r['message'] as String;
  }

  Future<Map<String, dynamic>> walletVerify({
    required String address,
    required String signature,
    String? inviteCode,
    String? cashtag,
    String? encPubkey,
  }) =>
      _call('POST', '/auth/wallet/verify', body: {
        'address': address,
        'signature': signature,
        if (inviteCode != null) 'invite_code': inviteCode,
        if (cashtag != null) 'cashtag': cashtag,
        if (encPubkey != null) 'enc_pubkey': encPubkey,
      });

  Future<Map<String, dynamic>> phoneRequest(String phone) =>
      _call('POST', '/auth/phone/request', body: {'phone': phone});

  Future<Map<String, dynamic>> phoneVerify({
    required String phone,
    required String code,
    String? inviteCode,
    String? cashtag,
    String? encPubkey,
  }) =>
      _call('POST', '/auth/phone/verify', body: {
        'phone': phone,
        'code': code,
        if (inviteCode != null) 'invite_code': inviteCode,
        if (cashtag != null) 'cashtag': cashtag,
        if (encPubkey != null) 'enc_pubkey': encPubkey,
      });

  // ------------------------------------------------------------ profile
  Future<Profile> me() async => Profile.fromJson(await _call('GET', '/me'));

  Future<Profile> changeCashtag(String newCashtag) async =>
      Profile.fromJson(await _call('POST', '/me/cashtag',
          body: {'new_cashtag': newCashtag}));

  Future<List<Map<String, dynamic>>> cashtagHistory() async {
    final r = await _call('GET', '/me/cashtag-history');
    return (r['history'] as List).cast<Map<String, dynamic>>();
  }

  Future<Profile> lookup(String cashtag) async => Profile.fromJson(
      await _call('GET', '/users/lookup', query: {'cashtag': cashtag}));

  // ------------------------------------------------------------ contacts
  Future<List<Profile>> contacts() async {
    final r = await _call('GET', '/contacts');
    return (r['contacts'] as List)
        .map((c) => Profile.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> addContact(String cashtag) =>
      _call('POST', '/contacts', body: {'cashtag': cashtag});

  // ------------------------------------------------------------ groups
  Future<GroupInfo> createGroup(String name, List<String> members) async =>
      GroupInfo.fromJson(await _call('POST', '/groups',
          body: {'name': name, 'members': members}));

  Future<List<GroupInfo>> groups() async {
    final r = await _call('GET', '/groups');
    return (r['groups'] as List)
        .map((g) => GroupInfo.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  Future<GroupInfo> group(int id) async =>
      GroupInfo.fromJson(await _call('GET', '/groups/$id'));

  // ------------------------------------------------------------ messages
  Future<List<Map<String, dynamic>>> sendMessage(
      Map<String, dynamic> body) async {
    final r = await _call('POST', '/messages', body: body);
    return (r['messages'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> ack(int messageId) =>
      _call('POST', '/messages/ack', body: {'message_id': messageId});

  // ------------------------------------------------------------ blobs
  Future<Map<String, dynamic>> uploadBlob(Map<String, dynamic> body) =>
      _call('POST', '/blobs', body: body);

  Future<Map<String, dynamic>> fetchBlob(String blobId) =>
      _call('GET', '/blobs/$blobId');
}
