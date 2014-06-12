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
EOT
    },
);

run_ctests(@tests);
