//
// It returns an array of objects of the form:
//  [
//    #{ uri: "path/to/page", page: PageObject }
// ]

// Param 1 should be `site.pages`
let pages = params[0];

// Loop through them and return all of the page objects that are in
// the table path.

let detail_pages = [];

// Get each table row, assigning it to {path: object}.
let keys = pages.keys();
for item in keys {
    if item.index_of("/content/table/") != 0 { continue; }
    let matter = pages[item];

    // Remove /content and .md
    let path = item.sub_string(8);
    path = path.sub_string(0, path.index_of(".md"));

    let row = #{
            uri: path,
            page: matter,
    };

    detail_pages.push(row),
}
// Newest to oldest, assuming you put the date in the URI
detail_pages.reverse();

