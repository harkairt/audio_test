import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class With10SecondDelay extends HookWidget {
  static runningFunction(String s) {
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
      sleep(Duration(seconds: 1));
      print(i);
      sum += i;
    }
    return "total sum is $sum";
  }

  pauseFunction() async {
    //pause function is not async
    // print(await compute(runningFunction, ''));
    print(runningFunction(''));
  }

  computeMeaningOfWorld() {}

  @override
  Widget build(BuildContext context) {
    final date = useState(DateTime.now());
    useEffect(() {
      Timer.periodic(Duration(seconds: 1), (timer) {
        date.value = DateTime.now();
      });
      return;
    }, []);

    // pauseFunction();
    return Material(
      child: Center(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(date.value.toString()),
              OutlineButton(onPressed: () {
                runningFunction('');
              }),
            ],
          ),
        ),
      ),
    );
  }
}
