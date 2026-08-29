import 'explore_search_api.dart';
import 'search_models.dart';

/// Repository는 화면/VM에서 쓸만한 인터페이스만 노출.
/// ※R-1: API 교체(REST → gRPC/GraphQL) 시 여기만 바꿔 끼움.
class ExploreSearchRepository {
  ExploreSearchRepository(this._api);
  final ExploreSearchApi _api;

  Future<PageResponsePS> searchFromQuery(Map<String, String> qp) {
    int? toInt(String? s) => (s == null || s.isEmpty) ? null : int.tryParse(s);
    List<String>? csv(String? s) => (s == null || s.trim().isEmpty)
        ? null
        : s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return _api.search(
      q: qp['q'],
      contentTypeId: toInt(qp['contentTypeId']),
      cat3List: csv(qp['cat3']),
      emotionCategoryId: toInt(qp['emotionCategoryId']),
      page: toInt(qp['page']) ?? 0,
      size: toInt(qp['size']) ?? 20,
      sort: qp['sort'],
    );
  }
}
