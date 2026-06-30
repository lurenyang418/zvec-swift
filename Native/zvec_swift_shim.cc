#include "zvec/zvec_swift_shim.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "zvec/db/collection.h"
#include "zvec/db/doc.h"
#include "zvec/db/query.h"

namespace {

zvec_error_code_t to_error(const zvec::Status &status) {
  const auto value = static_cast<int>(status.code());
  if (value < ZVEC_OK || value > ZVEC_ERROR_UNKNOWN) {
    return ZVEC_ERROR_UNKNOWN;
  }
  return static_cast<zvec_error_code_t>(value);
}

template <typename T>
zvec_error_code_t array_count(const zvec::Doc *doc, const char *field,
                              size_t *count) {
  const auto result = doc->get<T>(field);
  if (!result.has_value()) {
    return ZVEC_ERROR_INVALID_ARGUMENT;
  }
  *count = result->size();
  return ZVEC_OK;
}

std::optional<std::string> group_value(const zvec::Doc &doc,
                                       const zvec::FieldSchema &field) {
  const auto &name = field.name();
  switch (field.data_type()) {
    case zvec::DataType::BOOL: {
      auto value = doc.get<bool>(name);
      return value ? std::optional<std::string>(*value ? "true" : "false")
                   : std::nullopt;
    }
    case zvec::DataType::INT32: {
      auto value = doc.get<int32_t>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::INT64: {
      auto value = doc.get<int64_t>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::UINT32: {
      auto value = doc.get<uint32_t>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::UINT64: {
      auto value = doc.get<uint64_t>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::FLOAT: {
      auto value = doc.get<float>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::DOUBLE: {
      auto value = doc.get<double>(name);
      return value ? std::optional<std::string>(std::to_string(*value))
                   : std::nullopt;
    }
    case zvec::DataType::STRING:
      return doc.get<std::string>(name);
    default:
      return std::nullopt;
  }
}

}  // namespace

extern "C" {

zvec_error_code_t zvec_swift_doc_array_count(
    const zvec_doc_t *doc, const char *field_name, zvec_data_type_t field_type,
    size_t *count) {
  if (!doc || !field_name || !count) return ZVEC_ERROR_INVALID_ARGUMENT;
  const auto *value = reinterpret_cast<const zvec::Doc *>(doc);
  switch (field_type) {
    case ZVEC_DATA_TYPE_ARRAY_BINARY:
    case ZVEC_DATA_TYPE_ARRAY_STRING:
      return array_count<std::vector<std::string>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_BOOL:
      return array_count<std::vector<bool>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_INT32:
      return array_count<std::vector<int32_t>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_INT64:
      return array_count<std::vector<int64_t>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_UINT32:
      return array_count<std::vector<uint32_t>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_UINT64:
      return array_count<std::vector<uint64_t>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_FLOAT:
      return array_count<std::vector<float>>(value, field_name, count);
    case ZVEC_DATA_TYPE_ARRAY_DOUBLE:
      return array_count<std::vector<double>>(value, field_name, count);
    default:
      return ZVEC_ERROR_INVALID_ARGUMENT;
  }
}

zvec_error_code_t zvec_swift_doc_binary_array_element_copy(
    const zvec_doc_t *doc, const char *field_name, size_t index, uint8_t **data,
    size_t *size) {
  if (!doc || !field_name || !data || !size) return ZVEC_ERROR_INVALID_ARGUMENT;
  const auto *value = reinterpret_cast<const zvec::Doc *>(doc);
  const auto result = value->get<std::vector<std::string>>(field_name);
  if (!result.has_value() || index >= result->size()) {
    return ZVEC_ERROR_INVALID_ARGUMENT;
  }
  const auto &element = (*result)[index];
  *size = element.size();
  *data = static_cast<uint8_t *>(std::malloc(*size == 0 ? 1 : *size));
  if (!*data) return ZVEC_ERROR_RESOURCE_EXHAUSTED;
  if (*size != 0) std::memcpy(*data, element.data(), *size);
  return ZVEC_OK;
}

zvec_error_code_t zvec_swift_collection_group_by_query(
    const zvec_collection_t *collection,
    const zvec_group_by_vector_query_t *query,
    zvec_swift_group_result_t **results, size_t *result_count) {
  if (!collection || !query || !results || !result_count) {
    return ZVEC_ERROR_INVALID_ARGUMENT;
  }
  const auto *collection_ptr =
      reinterpret_cast<const std::shared_ptr<zvec::Collection> *>(collection);
  const auto *query_ptr = reinterpret_cast<const zvec::GroupByVectorQuery *>(query);
  auto schema = (*collection_ptr)->Schema();
  if (!schema.has_value()) return to_error(schema.error());
  const auto *group_field = schema->get_field(query_ptr->group_by_field_name_);
  if (!group_field || group_field->is_array_type() ||
      group_field->is_vector_field()) {
    return ZVEC_ERROR_INVALID_ARGUMENT;
  }
  auto stats = (*collection_ptr)->Stats();
  if (!stats.has_value()) return to_error(stats.error());
  if (stats->doc_count == 0) {
    *results = nullptr;
    *result_count = 0;
    return ZVEC_OK;
  }

  zvec::SearchQuery search;
  search.target_ = query_ptr->target_;
  search.topk_ = static_cast<int>(std::min<uint64_t>(stats->doc_count, 100000));
  search.filter_ = query_ptr->filter_;
  search.include_vector_ = query_ptr->include_vector_;
  search.output_fields_ = query_ptr->output_fields_;
  bool remove_group_field = false;
  if (search.output_fields_.has_value()) {
    auto &fields = *search.output_fields_;
    if (std::find(fields.begin(), fields.end(), query_ptr->group_by_field_name_) ==
        fields.end()) {
      fields.push_back(query_ptr->group_by_field_name_);
      remove_group_field = true;
    }
  }
  auto documents = (*collection_ptr)->Query(search);
  if (!documents.has_value()) return to_error(documents.error());

  std::vector<zvec::GroupResult> native;
  std::unordered_map<std::string, size_t> group_indices;
  native.reserve(query_ptr->group_count_);
  for (const auto &document : *documents) {
    auto value = group_value(*document, *group_field);
    if (!value.has_value()) continue;
    auto found = group_indices.find(*value);
    if (found == group_indices.end()) {
      if (native.size() >= query_ptr->group_count_) continue;
      found = group_indices.emplace(*value, native.size()).first;
      native.push_back(zvec::GroupResult{*value, {}});
    }
    auto &group = native[found->second];
    if (group.docs_.size() >= query_ptr->group_topk_) continue;
    group.docs_.push_back(*document);
    if (remove_group_field) group.docs_.back().remove(query_ptr->group_by_field_name_);
  }

  *result_count = native.size();
  *results = static_cast<zvec_swift_group_result_t *>(
      std::calloc(*result_count, sizeof(zvec_swift_group_result_t)));
  if (*result_count != 0 && !*results) return ZVEC_ERROR_RESOURCE_EXHAUSTED;

  for (size_t group_index = 0; group_index < *result_count; ++group_index) {
    const auto &group = native[group_index];
    auto &output = (*results)[group_index];
    output.group_value = ::strdup(group.group_by_value_.c_str());
    output.document_count = group.docs_.size();
    output.documents = static_cast<zvec_doc_t **>(
        std::calloc(output.document_count, sizeof(zvec_doc_t *)));
    if ((output.group_value == nullptr && !group.group_by_value_.empty()) ||
        (output.document_count != 0 && output.documents == nullptr)) {
      zvec_swift_group_results_free(*results, *result_count);
      *results = nullptr;
      *result_count = 0;
      return ZVEC_ERROR_RESOURCE_EXHAUSTED;
    }
    for (size_t doc_index = 0; doc_index < output.document_count; ++doc_index) {
      output.documents[doc_index] = reinterpret_cast<zvec_doc_t *>(
          new zvec::Doc(group.docs_[doc_index]));
    }
  }
  return ZVEC_OK;
}

void zvec_swift_group_results_free(zvec_swift_group_result_t *results,
                                   size_t result_count) {
  if (!results) return;
  for (size_t group_index = 0; group_index < result_count; ++group_index) {
    std::free(results[group_index].group_value);
    if (results[group_index].documents) {
      for (size_t doc_index = 0;
           doc_index < results[group_index].document_count; ++doc_index) {
        delete reinterpret_cast<zvec::Doc *>(
            results[group_index].documents[doc_index]);
      }
      std::free(results[group_index].documents);
    }
  }
  std::free(results);
}

}  // extern "C"
