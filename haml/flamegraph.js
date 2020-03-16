<![CDATA[
function s(g) { // show
    let info = g.children[0].firstChild.nodeValue
    let details = document.getElementById("details").firstChild;
    details.nodeValue = "method " + info;
}
function c() { // clear
    let details = document.getElementById("details").firstChild;
    details.nodeValue = ' ';
}
]]>
