#ifndef _HESSIAN_DEBUG_TEXT_H_
#define _HESSIAN_DEBUG_TEXT_H_

#include "objects.h"
#include <set>
#include <iosfwd>

namespace hessian {

/**
 * Debug Text output handle object
 *
 * @param obj dest object
 * @param os dest stream
 * @param indent current indent number
 * @param dejaVu outputed objects list
 */
typedef void (*debug_text_handler_pt)(const Object* obj,
                                      std::ostream& os,
                                      int indent,
                                      std::set<const Object*>* dejaVu);

/**
 * Extend Debug Text output handler
 *
 * @param type_id object type_id
 * @param handler object Debug Text output handle
 */
void debug_text_regist_handler(uint32_t type_id, debug_text_handler_pt handler);

/**
 * output object to os
 * @param obj dest object
 * @param os dest stream
 * @param indent current indent number
 * @param dejaVu outputed objects list
 */
void debug_text_handle_object(const Object* obj,
                              std::ostream& os,
                              int indent,
                              std::set<const Object*>* dejaVu);

/**
 * Check object outputed help
 * @return true: outputed
 *         false: not output
 */
bool debug_text_handle_dejaVu(const Object* obj,
                              std::ostream& os,
                              int indent,
                              std::set<const Object*>* dejaVu);

/**
 * Output items in List help
 */
void debug_text_handle_list_element(const List* list,
                                    std::ostream& os,
                                    int indent,
                                    std::set<const Object*>* dejaVu);

/**
 * Output key/value in Map help
 */
void debug_text_handle_map_element(const Map* map,
                                   std::ostream& os,
                                   int indent,
                                   std::set<const Object*>* dejaVu);

}
#endif
