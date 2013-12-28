#include "tracefile.h"

#include "rand.h"

#include <ctime>

using namespace devel::statprofiler;
using namespace std;

namespace {
    void append_hex(string &str, unsigned int value)
    {
        static const char digits[] = "0123456789abcdef";

        for (int i = 0; i < 8; ++i) {
            str += digits[value & 0xf];
            value >>= 4;
        }
    }
}

TraceFileWriter::TraceFileWriter(const string &path, bool is_template) :
    out(NULL), topmost_op_name(NULL)
{
    seed = rand_seed();
    open(path, is_template);
}

TraceFileWriter::~TraceFileWriter()
{
    close();
}

void TraceFileWriter::open(const std::string &path, bool is_template)
{
    close();
    output_file = path;

    if (is_template) {
        output_file += '.';
        append_hex(output_file, getpid());
        append_hex(output_file, time(NULL));
        for (int i = 0; i < 4; ++i) {
            rand(&seed);
            append_hex(output_file, seed);
        }
    }

    out = fopen(output_file.c_str(), "w");
}

void TraceFileWriter::close()
{
    if (out) {
        string temp = output_file + "_";

        fclose(out);
        if (!rename(temp.c_str(), output_file.c_str()))
            unlink(temp.c_str());
    }

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

void TraceFileWriter::add_topmost_op(pTHX_ OP *o)
{
    topmost_op_name = o ? OP_NAME(o) : NULL;
}

void TraceFileWriter::end_sample()
{
    fprintf(out, ";%s\n", topmost_op_name ? topmost_op_name : "");
}
