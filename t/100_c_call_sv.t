#!/usr/bin/env perl

use t::lib::Test;

my @tests = (
    {
        name   => 'exit called - trampoline',
        start  => 1,
        source => <<'EOT',
sub test {
    print "ok 1\n";
    exit 72;
}
EOT
        exit   => 72,
        # STDOUT is not flushed in this case
        stdout => <<'EOT',
EOT
    },
    {
        name   => 'exit called - no trampoline',
        start  => 0,
        source => <<'EOT',
sub test {
    Devel::StatProfiler::enable_profile();
    print "ok 1\n";
    exit 72;
}
EOT
        exit   => 72,
        # STDOUT is not flushed in this case
        stdout => <<'EOT',
EOT
    },
    {
        name   => 'exit called in eval - trampoline',
        start  => 1,
        source => <<'EOT',
sub test {
    eval {
        print "ok 1\n";
        exit 72;
    };
}
EOT
        exit   => 72,
        # STDOUT is not flushed in this case
        stdout => <<'EOT',
EOT
    },
    {
        name   => 'exit called - no trampoline',
        start  => 0,
        source => <<'EOT',
sub test {
    Devel::StatProfiler::enable_profile();
    eval {
        print "ok 1\n";
        exit 72;
    };
}
EOT
        exit   => 72,
        # STDOUT is not flushed in this case
        stdout => <<'EOT',
EOT
    },
    {
        name   => 'failed eval - trampoline',
        start  => 1,
        source => <<'EOT',
sub test {
    eval {
        print "ok 1\n";
        die;
        print "KO\n";
    } or do {
        print "ok 2\n";
    };
    print "ok 3\n";
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
ok 3
RES=1
EOT
    },
    {
        name   => 'successful eval - trampoline',
        start  => 1,
        source => <<'EOT',
sub test {
    eval {
        print "ok 1\n";
    } or do {
        print "KO\n";
    };
    print "ok 2\n";
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
RES=1
EOT
    },
    {
        name   => 'failed eval - no trampoline',
        start  => 0,
        source => <<'EOT',
sub test {
    Devel::StatProfiler::enable_profile();
    eval {
        print "ok 1\n";
        die;
        print "KO\n";
    } or do {
        print "ok 2\n";
    };
    Devel::StatProfiler::disable_profile();
    print "ok 3\n";
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
ok 3
RES=1
EOT
    },
    {
        name   => 'successful eval - no trampoline',
        start  => 0,
        source => <<'EOT',
sub test {
    Devel::StatProfiler::enable_profile();
    eval {
        print "ok 1\n";
    } or do {
        print "KO\n";
    };
    Devel::StatProfiler::disable_profile();
    print "ok 2\n";
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
RES=1
EOT
    },
    {
        name   => 'successful eval - no trampoline',
        start  => 0,
        source => <<'EOT',
sub test {
    Devel::StatProfiler::enable_profile();
    eval {
        print "ok 1\n";
    } or do {
        print "KO\n";
    };
    print "ok 2\n";
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
RES=1
EOT
    },
    {
        name   => 'no trampoline - all subs are traced',
        start  => 0,
        tests  => ['test1', 'test2'],
        source => <<'EOT',
sub test1 {
    Devel::StatProfiler::enable_profile();
    print "ok 1\n";
}

sub test2 {
    print "ok 2\n";
    Devel::StatProfiler::disable_profile();
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
ok 2
RES=1
RES=0
EOT
    },
    {
        name   => 'trampoline - return value',
        start  => 1,
        tests  => ['test1'],
        source => <<'EOT',
sub test1 {
    Devel::StatProfiler::enable_profile();
    print "ok 1\n";
    44;
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
RES=44
EOT
    },
    {
        name   => 'no trampoline - return value',
        start  => 0,
        tests  => ['test1'],
        source => <<'EOT',
sub test1 {
    Devel::StatProfiler::enable_profile();
    print "ok 1\n";
    44;
}
EOT
        exit   => 0,
        stdout => <<'EOT',
ok 1
RES=44
EOT
    },
);

run_ctests(@tests);
