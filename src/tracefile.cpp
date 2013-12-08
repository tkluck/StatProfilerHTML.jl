#include "tracefile.h"

using namespace devel::statprofiler;
using namespace std;


TraceFileWriter::TraceFileWriter(const string &path) :
    out(NULL)
{
    open(path);
}

TraceFileWriter::~TraceFileWriter()
{
    close();
}

void TraceFileWriter::open(const std::string &path)
{
    close();
    out = fopen(path.c_str(), "w");
}

void TraceFileWriter::close()
{
    if (out)
        fclose(out);
    out = NULL;
}

void TraceFileWriter::start_sample(unsigned int weight)
{
    fprintf(out, "%d", weight);
}

void TraceFileWriter::add_frame(unsigned int cxt_type, CV *sub, COP *line)
{
    fprintf(out, ";%d,", cxt_type);

    // require: cx->blk_eval.old_namesv
    // mPUSHs(newSVsv(cx->blk_eval.old_namesv));

    if (cxt_type != CXt_EVAL && cxt_type != CXt_NULL) {
        const char *package = "__ANON__", *name = "(unknown)";

        // from Perl_pp_caller
	GV * const cvgv = CvGV(sub);
	if (cvgv && isGV(cvgv)) {
            GV *egv = GvEGVx(cvgv) ? GvEGVx(cvgv) : cvgv;
            HV *stash = GvSTASH(egv);

            if (stash)
                package = HvNAME(stash);
            name = GvNAME(egv);
	}

        fprintf(out, "%s::%s,", package, name);
    } else
        fputs(",", out);

    fprintf(out, "%s,%d", OutCopFILE(line), CopLINE(line));
}

void TraceFileWriter::end_sample()
{
    fputs("\n", out);
}
