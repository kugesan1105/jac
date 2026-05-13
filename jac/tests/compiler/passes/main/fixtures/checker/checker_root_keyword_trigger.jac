node N {}

walker GoodWalker {
    can visit with Root entry {
        ;
    }  # valid - Root is the class

    can visit2 with Root | N entry {
        ;
    }  # valid - union of classes

}

walker BadWalker {
    can visit with root entry {
        ;
    }  # E1116 - root is a runtime instance

}

walker BadUnion {
    can visit with Root | root entry {
        ;
    }  # E1116 - root inside | union

}

walker BadTuple {
    can visit with (Root, root) entry {
        ;
    }  # E1116 - root inside tuple form

}
