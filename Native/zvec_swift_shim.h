#ifndef ZVEC_SWIFT_SHIM_H
#define ZVEC_SWIFT_SHIM_H

#include "c_api.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  char *group_value;
  zvec_doc_t **documents;
  size_t document_count;
} zvec_swift_group_result_t;

ZVEC_EXPORT zvec_error_code_t ZVEC_CALL zvec_swift_doc_array_count(
    const zvec_doc_t *doc, const char *field_name, zvec_data_type_t field_type,
    size_t *count);

ZVEC_EXPORT zvec_error_code_t ZVEC_CALL
zvec_swift_doc_binary_array_element_copy(const zvec_doc_t *doc,
                                         const char *field_name, size_t index,
                                         uint8_t **data, size_t *size);

ZVEC_EXPORT zvec_error_code_t ZVEC_CALL zvec_swift_collection_group_by_query(
    const zvec_collection_t *collection,
    const zvec_group_by_vector_query_t *query,
    zvec_swift_group_result_t **results, size_t *result_count);

ZVEC_EXPORT void ZVEC_CALL zvec_swift_group_results_free(
    zvec_swift_group_result_t *results, size_t result_count);

#ifdef __cplusplus
}
#endif

#endif
